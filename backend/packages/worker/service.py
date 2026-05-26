from __future__ import annotations

import time
from dataclasses import dataclass

from packages.account_analyzer.analyzer import analyze_account
from packages.common.env import env_int
from packages.github_analyzer.client import GitHubClient, discover_github_candidates
from packages.launch_feed.client import fetch_latest_launches
from packages.storage.repository import DetectRepository, postgres_connection
from packages.x_capture.client import FXTwitterClient
from packages.x_resolver.resolver import resolve_launch_identity


@dataclass(slots=True)
class WorkerStats:
    launches_seen: int = 0
    launches_processed: int = 0
    accounts_completed: int = 0
    errors: int = 0


def run_once(*, limit: int | None = None) -> WorkerStats:
    target_tweets = env_int("DETECT_TARGET_TWEETS", 50)
    max_x_pages = env_int("DETECT_MAX_X_PAGES", 10)
    launches = fetch_latest_launches()
    if limit is not None:
        launches = launches[: max(0, limit)]
    stats = WorkerStats(launches_seen=len(launches))
    x_client = FXTwitterClient()
    github_client = GitHubClient()
    with postgres_connection() as conn:
        repo = DetectRepository(conn)
        for launch in launches:
            launch_id = repo.upsert_launch(launch)
            stats.launches_processed += 1
            try:
                identity = resolve_launch_identity(launch, x_client)
                if identity is None:
                    repo.set_launch_stage(launch_id, "failed", "Unable to resolve X identity.")
                    stats.errors += 1
                    continue
                repo.set_launch_stage(launch_id, "identity_resolved")
                profile, posts, fetch_meta = x_client.fetch_user_history(
                    identity.username,
                    target_tweets=target_tweets,
                    max_pages=max_x_pages,
                )
                account_id = repo.upsert_account(
                    launch_id=launch_id,
                    identity=identity,
                    profile=profile,
                    posts=posts,
                    fetch_meta=fetch_meta,
                    stage="x_fetched",
                )
                repo.set_launch_stage(launch_id, "x_fetched")
                github_repos = []
                repo.set_account_stage(account_id, "github_scanning")
                for url, source in discover_github_candidates(
                    launch_website_url=launch.website_url,
                    profile=profile,
                    posts=posts,
                )[:5]:
                    try:
                        signal = github_client.analyze_repo_url(url, source=source)
                    except Exception:
                        continue
                    if signal:
                        github_repos.append(signal)
                        repo.upsert_github_repo(account_id, signal)
                repo.set_account_stage(account_id, "github_scanned")
                repo.set_account_stage(account_id, "ai_analyzing")
                assessment = analyze_account(
                    launch=launch,
                    identity=identity,
                    profile=profile,
                    posts=posts,
                    github_repos=github_repos,
                )
                repo.upsert_assessment(account_id, assessment)
                repo.set_account_stage(account_id, "completed")
                repo.set_launch_stage(launch_id, "completed")
                stats.accounts_completed += 1
            except Exception as exc:
                repo.set_launch_stage(launch_id, "failed", str(exc))
                stats.errors += 1
    return stats


def run_worker() -> None:
    poll_seconds = max(5, env_int("DETECT_POLL_SECONDS", 20))
    while True:
        started = time.time()
        try:
            stats = run_once()
            print(
                "[detect-worker] "
                f"seen={stats.launches_seen} processed={stats.launches_processed} "
                f"completed={stats.accounts_completed} errors={stats.errors}",
                flush=True,
            )
        except Exception as exc:
            print(f"[detect-worker] run failed: {exc}", flush=True)
        elapsed = time.time() - started
        time.sleep(max(1.0, poll_seconds - elapsed))

