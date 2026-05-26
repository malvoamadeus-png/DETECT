from __future__ import annotations

from typing import Any

import pytest

from packages.account_analyzer import analyzer
from packages.common.models import GithubRepoSignal, LaunchRecord, XIdentity, XPost, XProfile


def _launch() -> LaunchRecord:
    return LaunchRecord(
        activity_id="launch-1",
        token_name="Detect Token",
        token_symbol="DTC",
        chain="base",
        token_address="0x123",
        launch_type="launch",
        status="created",
        tx_hash="0xabc",
        pool_id="",
        website_url="https://example.com",
        tweet_url="https://x.com/bankr/status/1",
        metadata_uri="",
        image_uri="",
        timestamp_ms=None,
    )


def _identity() -> XIdentity:
    return XIdentity(
        username="builder",
        source="test",
        profile_url="https://x.com/builder",
        confidence=90,
    )


def _profile() -> XProfile:
    return XProfile(
        username="builder",
        display_name="Builder",
        description="Building crypto agent tools on Base.",
        followers=1200,
        following=100,
        statuses=500,
        website_url="https://github.com/example/repo",
        avatar_url="",
        banner_url="",
        joined="",
        raw_payload={},
    )


def _post(tweet_id: str, text: str = "Shipping a crypto API demo") -> XPost:
    return XPost(
        tweet_id=tweet_id,
        author_username="builder",
        author_display_name="Builder",
        url=f"https://x.com/builder/status/{tweet_id}",
        text=text,
        created_at_raw="",
        created_timestamp=1,
        reply_count=2,
        repost_count=3,
        like_count=11,
        bookmark_count=0,
        view_count=100,
        media_urls=[],
        raw_payload={},
    )


class FakeResponse:
    def __init__(self, payload: dict[str, Any], status_error: Exception | None = None) -> None:
        self.payload = payload
        self.status_error = status_error

    def raise_for_status(self) -> None:
        if self.status_error:
            raise self.status_error

    def json(self) -> dict[str, Any]:
        return self.payload


def test_analyze_account_uses_heuristic_without_openai_env(monkeypatch) -> None:
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_BASE_URL", raising=False)

    result = analyzer.analyze_account(
        launch=_launch(),
        identity=_identity(),
        profile=_profile(),
        posts=[_post("1")],
        github_repos=[],
    )

    assert result.model == "heuristic"
    assert result.verdict in {"likely_accept", "likely_tolerate", "unclear", "likely_reject"}
    assert "Heuristic fallback" in result.risks[0]


def test_analyze_account_normalizes_successful_model_response(monkeypatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("OPENAI_BASE_URL", "https://openai.example/v1/")
    monkeypatch.setenv("OPENAI_MODEL", "gpt-5.4-mini")

    def fake_post(*args: Any, **kwargs: Any) -> FakeResponse:
        assert args[0] == "https://openai.example/v1/chat/completions"
        assert kwargs["headers"]["Authorization"] == "Bearer test-key"
        return FakeResponse(
            {
                "model": "gpt-5.4-mini",
                "choices": [
                    {
                        "message": {
                            "content": '{"archetype":"ai_builder","verdict":"likely_accept","summary":"Looks receptive.","scores":{"crypto_affinity":150,"risk":-5},"reasons":["Builds in crypto."],"risks":[],"evidence":["Bio mentions Base."]}'
                        }
                    }
                ],
            }
        )

    monkeypatch.setattr(analyzer.requests, "post", fake_post)

    result = analyzer.analyze_account(
        launch=_launch(),
        identity=_identity(),
        profile=_profile(),
        posts=[_post("1")],
        github_repos=[
            GithubRepoSignal(
                owner="example",
                repo="repo",
                canonical_url="https://github.com/example/repo",
                source="profile",
                score=70,
            )
        ],
    )

    assert result.model == "gpt-5.4-mini"
    assert result.archetype == "ai_builder"
    assert result.verdict == "likely_accept"
    assert result.scores["crypto_affinity"] == 100
    assert result.scores["risk"] == 0


@pytest.mark.parametrize(
    "payload,status_error",
    [
        ({"choices": [{"message": {"content": "not-json"}}]}, None),
        ({}, RuntimeError("HTTP 500")),
    ],
)
def test_analyze_account_falls_back_on_model_errors(monkeypatch, payload: dict[str, Any], status_error: Exception | None) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("OPENAI_BASE_URL", "https://openai.example/v1")

    def fake_post(*args: Any, **kwargs: Any) -> FakeResponse:
        return FakeResponse(payload, status_error=status_error)

    monkeypatch.setattr(analyzer.requests, "post", fake_post)

    result = analyzer.analyze_account(
        launch=_launch(),
        identity=_identity(),
        profile=_profile(),
        posts=[_post("1")],
        github_repos=[],
    )

    assert result.model == "heuristic"
    assert any(risk.startswith("Model call failed:") for risk in result.risks)
