from __future__ import annotations

from typing import Any

from packages.common.models import LaunchRecord, XIdentity
from packages.worker import service as worker_service


class FakeFXTwitterClient:
    fetch_calls: list[dict[str, Any]] = []

    def fetch_user_history(self, username: str, *, target_tweets: int, max_pages: int):
        self.fetch_calls.append(
            {"username": username, "target_tweets": target_tweets, "max_pages": max_pages}
        )
        return None, [], {"attempts": [], "target_reached": False}


class FakeGitHubClient:
    pass


class FakeRepo:
    upsert_account_calls: list[dict[str, Any]] = []

    def __init__(self, _conn: object) -> None:
        self.account_stage: list[str] = []

    def upsert_launch(self, launch: LaunchRecord) -> int:
        return 1

    def set_launch_stage(self, launch_id: int, stage: str, message: str = "") -> None:
        pass

    def upsert_account(self, **kwargs: Any) -> int:
        self.upsert_account_calls.append(kwargs)
        return 10

    def set_account_stage(self, account_id: int, stage: str, message: str = "") -> None:
        self.account_stage.append(stage)

    def upsert_github_repo(self, account_id: int, signal: object) -> None:
        pass

    def upsert_assessment(self, account_id: int, assessment: object) -> None:
        pass


class FakeConnection:
    def __enter__(self) -> object:
        return object()

    def __exit__(self, *args: object) -> None:
        pass


def _launch() -> LaunchRecord:
    return LaunchRecord(
        activity_id="launch-1",
        token_name="Token",
        token_symbol="TOK",
        chain="base",
        token_address="0x123",
        launch_type="launch",
        status="created",
        tx_hash="0xabc",
        pool_id="",
        website_url="",
        tweet_url="",
        metadata_uri="",
        image_uri="",
        timestamp_ms=None,
    )


def test_run_once_defaults_to_50_target_tweets_and_10_x_pages(monkeypatch) -> None:
    FakeFXTwitterClient.fetch_calls = []
    FakeRepo.upsert_account_calls = []

    monkeypatch.delenv("DETECT_TARGET_TWEETS", raising=False)
    monkeypatch.delenv("DETECT_MAX_X_PAGES", raising=False)
    monkeypatch.setattr(worker_service, "fetch_latest_launches", lambda: [_launch()])
    monkeypatch.setattr(worker_service, "postgres_connection", lambda: FakeConnection())
    monkeypatch.setattr(worker_service, "DetectRepository", FakeRepo)
    monkeypatch.setattr(worker_service, "FXTwitterClient", FakeFXTwitterClient)
    monkeypatch.setattr(worker_service, "GitHubClient", FakeGitHubClient)
    monkeypatch.setattr(worker_service, "discover_github_candidates", lambda **_: [])
    monkeypatch.setattr(
        worker_service,
        "resolve_launch_identity",
        lambda launch, x_client: XIdentity(
            username="Target",
            source="test",
            profile_url="https://x.com/Target",
            confidence=90,
        ),
    )
    monkeypatch.setattr(worker_service, "analyze_account", lambda **_: object())

    stats = worker_service.run_once(limit=1)

    assert stats.launches_seen == 1
    assert stats.launches_processed == 1
    assert stats.accounts_completed == 1
    assert FakeFXTwitterClient.fetch_calls == [
        {"username": "Target", "target_tweets": 50, "max_pages": 10}
    ]
    assert FakeRepo.upsert_account_calls[0]["target_tweets"] == 50


def test_run_once_persists_configured_target_tweets(monkeypatch) -> None:
    FakeFXTwitterClient.fetch_calls = []
    FakeRepo.upsert_account_calls = []

    monkeypatch.setenv("DETECT_TARGET_TWEETS", "37")
    monkeypatch.setenv("DETECT_MAX_X_PAGES", "4")
    monkeypatch.setattr(worker_service, "fetch_latest_launches", lambda: [_launch()])
    monkeypatch.setattr(worker_service, "postgres_connection", lambda: FakeConnection())
    monkeypatch.setattr(worker_service, "DetectRepository", FakeRepo)
    monkeypatch.setattr(worker_service, "FXTwitterClient", FakeFXTwitterClient)
    monkeypatch.setattr(worker_service, "GitHubClient", FakeGitHubClient)
    monkeypatch.setattr(worker_service, "discover_github_candidates", lambda **_: [])
    monkeypatch.setattr(
        worker_service,
        "resolve_launch_identity",
        lambda launch, x_client: XIdentity(
            username="Target",
            source="test",
            profile_url="https://x.com/Target",
            confidence=90,
        ),
    )
    monkeypatch.setattr(worker_service, "analyze_account", lambda **_: object())

    worker_service.run_once(limit=1)

    assert FakeFXTwitterClient.fetch_calls == [
        {"username": "Target", "target_tweets": 37, "max_pages": 4}
    ]
    assert FakeRepo.upsert_account_calls[0]["target_tweets"] == 37


def test_run_worker_defaults_to_20_second_poll(monkeypatch) -> None:
    sleeps: list[float] = []

    monkeypatch.delenv("DETECT_POLL_SECONDS", raising=False)
    monkeypatch.setattr(worker_service, "run_once", lambda: worker_service.WorkerStats())
    monkeypatch.setattr(worker_service.time, "time", lambda: 100.0)

    def fake_sleep(seconds: float) -> None:
        sleeps.append(seconds)
        raise KeyboardInterrupt

    monkeypatch.setattr(worker_service.time, "sleep", fake_sleep)

    try:
        worker_service.run_worker()
    except KeyboardInterrupt:
        pass

    assert sleeps == [20.0]
