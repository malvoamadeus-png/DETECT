from __future__ import annotations

import math
import os
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse

import requests

from packages.common.models import GithubRepoSignal, XPost, XProfile


GITHUB_RE = re.compile(r"https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


def normalize_github_repo_url(url: str) -> tuple[str, str, str] | None:
    raw = url.strip()
    if not raw:
        return None
    if "://" not in raw:
        raw = "https://" + raw.lstrip("/")
    parsed = urlparse(raw)
    if parsed.netloc.lower() not in {"github.com", "www.github.com"}:
        return None
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 2:
        return None
    owner = parts[0]
    repo = parts[1].removesuffix(".git")
    if not owner or not repo:
        return None
    return owner, repo, f"https://github.com/{owner}/{repo}"


def extract_github_urls(text: str) -> list[str]:
    found: list[str] = []
    for match in GITHUB_RE.findall(text or ""):
        normalized = normalize_github_repo_url(match)
        if normalized:
            found.append(normalized[2])
    return list(dict.fromkeys(found))


def discover_github_candidates(
    *,
    launch_website_url: str,
    profile: XProfile | None,
    posts: list[XPost],
) -> list[tuple[str, str]]:
    candidates: list[tuple[str, str]] = []
    normalized = normalize_github_repo_url(launch_website_url)
    if normalized:
        candidates.append((normalized[2], "launch_website_repo"))
    if profile and profile.website_url:
        normalized = normalize_github_repo_url(profile.website_url)
        if normalized:
            candidates.append((normalized[2], "profile_repo"))
    for post in posts[:20]:
        for url in extract_github_urls(post.text):
            candidates.append((url, "mentioned_repo"))
    deduped: dict[str, str] = {}
    for url, source in candidates:
        deduped.setdefault(url, source)
    return [(url, source) for url, source in deduped.items()]


class GitHubClient:
    def __init__(self) -> None:
        self.token = os.getenv("GITHUB_TOKEN", "").strip()

    def _get(self, url: str) -> Any:
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "detect-token-intel/0.1",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        response = requests.get(url, headers=headers, timeout=25)
        response.raise_for_status()
        return response.json()

    def analyze_repo_url(self, url: str, *, source: str) -> GithubRepoSignal | None:
        normalized = normalize_github_repo_url(url)
        if not normalized:
            return None
        owner, repo, canonical = normalized
        api_base = f"https://api.github.com/repos/{owner}/{repo}"
        repo_payload = self._get(api_base)
        languages = self._get(f"{api_base}/languages")
        contributors = self._get(f"{api_base}/contributors?per_page=10")
        releases = self._get(f"{api_base}/releases?per_page=5")
        if not isinstance(languages, dict):
            languages = {}
        if not isinstance(contributors, list):
            contributors = []
        if not isinstance(releases, list):
            releases = []
        topics = repo_payload.get("topics")
        if not isinstance(topics, list):
            topics = []
        score_breakdown = score_repo(repo_payload, contributors, releases)
        score = min(100, sum(score_breakdown.values()))
        license_payload = repo_payload.get("license") if isinstance(repo_payload.get("license"), dict) else {}
        return GithubRepoSignal(
            owner=owner,
            repo=repo,
            canonical_url=canonical,
            source=source,
            full_name=str(repo_payload.get("full_name") or f"{owner}/{repo}"),
            description=str(repo_payload.get("description") or ""),
            stars=int(repo_payload.get("stargazers_count") or 0),
            forks=int(repo_payload.get("forks_count") or 0),
            subscribers=int(repo_payload.get("subscribers_count") or 0),
            open_issues=int(repo_payload.get("open_issues_count") or 0),
            language=str(repo_payload.get("language") or ""),
            pushed_at=str(repo_payload.get("pushed_at") or ""),
            created_at=str(repo_payload.get("created_at") or ""),
            license_spdx=str(license_payload.get("spdx_id") or ""),
            topics=[str(topic) for topic in topics],
            languages={str(k): int(v) for k, v in languages.items()},
            contributors=[
                {"login": item.get("login"), "contributions": item.get("contributions")}
                for item in contributors
                if isinstance(item, dict)
            ],
            releases=[
                {"tag_name": item.get("tag_name"), "published_at": item.get("published_at")}
                for item in releases
                if isinstance(item, dict)
            ],
            score=score,
            score_breakdown=score_breakdown,
            raw_payload={"repo": repo_payload, "languages": languages, "contributors": contributors, "releases": releases},
        )


def _days_since(value: str) -> int | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return max(0, (datetime.now(timezone.utc) - parsed).days)


def _log_points(value: int, cap: int, scale: float) -> int:
    if value <= 0:
        return 0
    return min(cap, int(round(math.log10(value + 1) * scale)))


def score_repo(repo: dict[str, Any], contributors: list[Any], releases: list[Any]) -> dict[str, int]:
    pushed_days = _days_since(str(repo.get("pushed_at") or ""))
    activity = 0
    if pushed_days is not None:
        if pushed_days <= 7:
            activity += 22
        elif pushed_days <= 30:
            activity += 16
        elif pushed_days <= 90:
            activity += 9
        else:
            activity += 3
    if releases:
        activity += 8
    if int(repo.get("open_issues_count") or 0) >= 0:
        activity += 3
    activity = min(35, activity)

    community = _log_points(int(repo.get("stargazers_count") or 0), 17, 4.5)
    community += _log_points(int(repo.get("forks_count") or 0), 6, 3.0)
    community += _log_points(int(repo.get("subscribers_count") or 0), 2, 1.0)
    community = min(25, community)

    valid_contributors = [item for item in contributors if isinstance(item, dict)]
    collaboration = min(14, len(valid_contributors) * 3)
    if str((repo.get("owner") or {}).get("type") or "") == "Organization":
        collaboration += 4
    if len(valid_contributors) == 1:
        collaboration = max(0, collaboration - 2)
    collaboration = min(20, collaboration)

    completeness = 0
    if repo.get("license"):
        completeness += 5
    if repo.get("description"):
        completeness += 4
    if repo.get("homepage"):
        completeness += 4
    if repo.get("topics"):
        completeness += 4
    if releases:
        completeness += 3
    completeness = min(20, completeness)
    return {
        "activity": activity,
        "community": community,
        "collaboration": collaboration,
        "completeness": completeness,
    }
