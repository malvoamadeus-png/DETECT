from __future__ import annotations

import json
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Iterator
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from packages.account_analyzer.analyzer import interaction_summary
from packages.common.env import database_url
from packages.common.models import AccountAssessment, GithubRepoSignal, LaunchRecord, Stage, XIdentity, XPost, XProfile


@contextmanager
def postgres_connection() -> Iterator[psycopg.Connection[dict[str, Any]]]:
    conn = psycopg.connect(database_url(), row_factory=dict_row)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def jsonb(value: Any) -> Jsonb:
    return Jsonb(value)


def launched_at(timestamp_ms: int | None) -> datetime | None:
    if timestamp_ms is None:
        return None
    return datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)


class DetectRepository:
    def __init__(self, conn: psycopg.Connection[dict[str, Any]]) -> None:
        self.conn = conn

    def upsert_launch(self, launch: LaunchRecord) -> str:
        row = self.conn.execute(
            """
            INSERT INTO detect_launches (
              activity_id, token_name, token_symbol, chain, token_address, launch_type,
              launch_status, tx_hash, pool_id, website_url, tweet_url, metadata_uri,
              image_uri, launched_at, deployer_json, fee_recipient_json, raw_payload_json,
              processing_stage, updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'discovered', now())
            ON CONFLICT(activity_id) DO UPDATE SET
              token_name = EXCLUDED.token_name,
              token_symbol = EXCLUDED.token_symbol,
              chain = EXCLUDED.chain,
              token_address = EXCLUDED.token_address,
              launch_type = EXCLUDED.launch_type,
              launch_status = EXCLUDED.launch_status,
              tx_hash = EXCLUDED.tx_hash,
              pool_id = EXCLUDED.pool_id,
              website_url = EXCLUDED.website_url,
              tweet_url = EXCLUDED.tweet_url,
              metadata_uri = EXCLUDED.metadata_uri,
              image_uri = EXCLUDED.image_uri,
              launched_at = COALESCE(EXCLUDED.launched_at, detect_launches.launched_at),
              deployer_json = EXCLUDED.deployer_json,
              fee_recipient_json = EXCLUDED.fee_recipient_json,
              raw_payload_json = EXCLUDED.raw_payload_json,
              updated_at = now()
            RETURNING id
            """,
            (
                launch.activity_id,
                launch.token_name,
                launch.token_symbol,
                launch.chain,
                launch.token_address,
                launch.launch_type,
                launch.status,
                launch.tx_hash,
                launch.pool_id,
                launch.website_url,
                launch.tweet_url,
                launch.metadata_uri,
                launch.image_uri,
                launched_at(launch.timestamp_ms),
                jsonb(launch.deployer),
                jsonb(launch.fee_recipient),
                jsonb(launch.raw_payload),
            ),
        ).fetchone()
        if row is None:
            raise RuntimeError(f"Failed to upsert launch {launch.activity_id}")
        return str(row["id"])

    def set_launch_stage(self, launch_id: str, stage: Stage, error: str | None = None) -> None:
        self.conn.execute(
            "UPDATE detect_launches SET processing_stage = %s, processing_error = %s, updated_at = now() WHERE id = %s",
            (stage, error, launch_id),
        )

    def upsert_account(
        self,
        *,
        launch_id: str,
        identity: XIdentity,
        profile: XProfile | None,
        posts: list[XPost],
        target_tweets: int,
        fetch_meta: dict[str, Any],
        stage: Stage,
    ) -> str:
        profile = profile or XProfile(
            username=identity.username,
            display_name=identity.username,
            description="",
            followers=0,
            following=0,
            statuses=0,
            website_url="",
            avatar_url="",
            banner_url="",
            joined="",
            raw_payload={},
        )
        row = self.conn.execute(
            """
            INSERT INTO detect_accounts (
              launch_id, username, username_lower, identity_source, identity_confidence,
              profile_url, display_name, description, followers, following, statuses,
              website_url, avatar_url, banner_url, joined_raw, x_posts_collected,
              x_posts_target, x_fetch_meta_json, interaction_json, processing_stage, updated_at
            )
            VALUES (%s, %s, lower(%s), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
            ON CONFLICT(launch_id, username_lower) DO UPDATE SET
              identity_source = EXCLUDED.identity_source,
              identity_confidence = EXCLUDED.identity_confidence,
              profile_url = EXCLUDED.profile_url,
              display_name = EXCLUDED.display_name,
              description = EXCLUDED.description,
              followers = EXCLUDED.followers,
              following = EXCLUDED.following,
              statuses = EXCLUDED.statuses,
              website_url = EXCLUDED.website_url,
              avatar_url = EXCLUDED.avatar_url,
              banner_url = EXCLUDED.banner_url,
              joined_raw = EXCLUDED.joined_raw,
              x_posts_collected = EXCLUDED.x_posts_collected,
              x_fetch_meta_json = EXCLUDED.x_fetch_meta_json,
              interaction_json = EXCLUDED.interaction_json,
              processing_stage = EXCLUDED.processing_stage,
              updated_at = now()
            RETURNING id
            """,
            (
                launch_id,
                identity.username,
                identity.username,
                identity.source,
                identity.confidence,
                identity.profile_url,
                profile.display_name,
                profile.description,
                profile.followers,
                profile.following,
                profile.statuses,
                profile.website_url,
                profile.avatar_url,
                profile.banner_url,
                profile.joined,
                len(posts),
                target_tweets,
                jsonb(fetch_meta),
                jsonb(interaction_summary(posts)),
                stage,
            ),
        ).fetchone()
        if row is None:
            raise RuntimeError(f"Failed to upsert account {identity.username}")
        account_id = str(row["id"])
        for post in posts:
            self.upsert_post(account_id, post)
        return account_id

    def set_account_stage(self, account_id: str, stage: Stage, error: str | None = None) -> None:
        self.conn.execute(
            "UPDATE detect_accounts SET processing_stage = %s, processing_error = %s, updated_at = now() WHERE id = %s",
            (stage, error, account_id),
        )

    def upsert_post(self, account_id: str, post: XPost) -> None:
        self.conn.execute(
            """
            INSERT INTO detect_x_posts (
              account_id, tweet_id, author_username, author_display_name, url, body_text,
              created_at_raw, created_timestamp, reply_count, repost_count, like_count,
              bookmark_count, view_count, media_urls_json, raw_payload_json
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT(tweet_id) DO UPDATE SET
              account_id = EXCLUDED.account_id,
              author_username = EXCLUDED.author_username,
              author_display_name = EXCLUDED.author_display_name,
              url = EXCLUDED.url,
              body_text = EXCLUDED.body_text,
              created_at_raw = EXCLUDED.created_at_raw,
              created_timestamp = EXCLUDED.created_timestamp,
              reply_count = EXCLUDED.reply_count,
              repost_count = EXCLUDED.repost_count,
              like_count = EXCLUDED.like_count,
              bookmark_count = EXCLUDED.bookmark_count,
              view_count = EXCLUDED.view_count,
              media_urls_json = EXCLUDED.media_urls_json,
              raw_payload_json = EXCLUDED.raw_payload_json
            """,
            (
                account_id,
                post.tweet_id,
                post.author_username,
                post.author_display_name,
                post.url,
                post.text,
                post.created_at_raw,
                post.created_timestamp,
                post.reply_count,
                post.repost_count,
                post.like_count,
                post.bookmark_count,
                post.view_count,
                jsonb(post.media_urls),
                jsonb(post.raw_payload),
            ),
        )

    def upsert_github_repo(self, account_id: str, repo: GithubRepoSignal) -> None:
        self.conn.execute(
            """
            INSERT INTO detect_github_repos (
              account_id, canonical_url, source, owner, repo, full_name, description,
              stars, forks, subscribers, open_issues, language, pushed_at, created_at_raw,
              license_spdx, topics_json, languages_json, contributors_json, releases_json,
              score, score_breakdown_json, raw_payload_json, updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
            ON CONFLICT(account_id, canonical_url) DO UPDATE SET
              source = EXCLUDED.source,
              full_name = EXCLUDED.full_name,
              description = EXCLUDED.description,
              stars = EXCLUDED.stars,
              forks = EXCLUDED.forks,
              subscribers = EXCLUDED.subscribers,
              open_issues = EXCLUDED.open_issues,
              language = EXCLUDED.language,
              pushed_at = EXCLUDED.pushed_at,
              license_spdx = EXCLUDED.license_spdx,
              topics_json = EXCLUDED.topics_json,
              languages_json = EXCLUDED.languages_json,
              contributors_json = EXCLUDED.contributors_json,
              releases_json = EXCLUDED.releases_json,
              score = EXCLUDED.score,
              score_breakdown_json = EXCLUDED.score_breakdown_json,
              raw_payload_json = EXCLUDED.raw_payload_json,
              updated_at = now()
            """,
            (
                account_id,
                repo.canonical_url,
                repo.source,
                repo.owner,
                repo.repo,
                repo.full_name,
                repo.description,
                repo.stars,
                repo.forks,
                repo.subscribers,
                repo.open_issues,
                repo.language,
                repo.pushed_at,
                repo.created_at,
                repo.license_spdx,
                jsonb(repo.topics),
                jsonb(repo.languages),
                jsonb(repo.contributors),
                jsonb(repo.releases),
                repo.score,
                jsonb(repo.score_breakdown),
                jsonb(repo.raw_payload),
            ),
        )

    def upsert_assessment(self, account_id: str, assessment: AccountAssessment) -> None:
        self.conn.execute(
            """
            INSERT INTO detect_account_assessments (
              account_id, archetype, verdict, summary, scores_json, reasons_json,
              risks_json, evidence_json, model, raw_payload_json, updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
            ON CONFLICT(account_id) DO UPDATE SET
              archetype = EXCLUDED.archetype,
              verdict = EXCLUDED.verdict,
              summary = EXCLUDED.summary,
              scores_json = EXCLUDED.scores_json,
              reasons_json = EXCLUDED.reasons_json,
              risks_json = EXCLUDED.risks_json,
              evidence_json = EXCLUDED.evidence_json,
              model = EXCLUDED.model,
              raw_payload_json = EXCLUDED.raw_payload_json,
              updated_at = now()
            """,
            (
                account_id,
                assessment.archetype,
                assessment.verdict,
                assessment.summary,
                jsonb(assessment.scores),
                jsonb(assessment.reasons),
                jsonb(assessment.risks),
                jsonb(assessment.evidence),
                assessment.model,
                jsonb(assessment.raw_payload),
            ),
        )

    def list_dashboard(self, limit: int = 60) -> list[dict[str, Any]]:
        rows = self.conn.execute(
            "SELECT * FROM detect_dashboard ORDER BY discovered_at DESC LIMIT %s",
            (max(1, min(limit, 500)),),
        ).fetchall()
        return [self._json_safe(dict(row)) for row in rows]

    def _json_safe(self, row: dict[str, Any]) -> dict[str, Any]:
        for key, value in list(row.items()):
            row[key] = self._json_safe_value(value)
        return row

    def _json_safe_value(self, value: Any) -> Any:
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, UUID):
            return str(value)
        if isinstance(value, list):
            return [self._json_safe_value(item) for item in value]
        if isinstance(value, dict):
            return {str(key): self._json_safe_value(item) for key, item in value.items()}
        return value
