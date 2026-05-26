from __future__ import annotations

from typing import Any

from packages.common.models import XPost, XProfile
from packages.github_analyzer import client as github_client_module


def _post(text: str) -> XPost:
    return XPost(
        tweet_id="1",
        author_username="builder",
        author_display_name="Builder",
        url="https://x.com/builder/status/1",
        text=text,
        created_at_raw="",
        created_timestamp=1,
        reply_count=0,
        repost_count=0,
        like_count=0,
        bookmark_count=0,
        view_count=0,
        media_urls=[],
        raw_payload={},
    )


def _profile(url: str) -> XProfile:
    return XProfile(
        username="builder",
        display_name="Builder",
        description="",
        followers=0,
        following=0,
        statuses=0,
        website_url=url,
        avatar_url="",
        banner_url="",
        joined="",
        raw_payload={},
    )


def test_normalize_github_repo_url_handles_git_suffix_and_rejects_non_repo() -> None:
    assert github_client_module.normalize_github_repo_url("github.com/Owner/Repo.git") == (
        "Owner",
        "Repo",
        "https://github.com/Owner/Repo",
    )
    assert github_client_module.normalize_github_repo_url("https://github.com/Owner") is None
    assert github_client_module.normalize_github_repo_url("https://example.com/Owner/Repo") is None


def test_extract_github_urls_dedupes_mentions() -> None:
    text = "See https://github.com/a/b and https://github.com/a/b plus https://github.com/c/d/issues"

    assert github_client_module.extract_github_urls(text) == [
        "https://github.com/a/b",
        "https://github.com/c/d",
    ]


def test_discover_github_candidates_preserves_first_source_and_dedupes() -> None:
    candidates = github_client_module.discover_github_candidates(
        launch_website_url="https://github.com/a/b",
        profile=_profile("https://github.com/a/b"),
        posts=[_post("repo https://github.com/c/d")],
    )

    assert candidates == [
        ("https://github.com/a/b", "launch_website_repo"),
        ("https://github.com/c/d", "mentioned_repo"),
    ]


def test_score_repo_rewards_activity_community_collaboration_and_completeness(monkeypatch) -> None:
    class FixedDateTime(github_client_module.datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 5, 26, tzinfo=tz)

    monkeypatch.setattr(github_client_module, "datetime", FixedDateTime)

    score = github_client_module.score_repo(
        {
            "pushed_at": "2026-05-24T00:00:00Z",
            "open_issues_count": 2,
            "stargazers_count": 999,
            "forks_count": 50,
            "subscribers_count": 10,
            "owner": {"type": "Organization"},
            "license": {"spdx_id": "MIT"},
            "description": "Useful repo",
            "homepage": "https://example.com",
            "topics": ["ai", "crypto"],
        },
        contributors=[{"login": "a"}, {"login": "b"}, {"login": "c"}],
        releases=[{"tag_name": "v1"}],
    )

    assert score["activity"] == 33
    assert score["community"] > 0
    assert score["collaboration"] == 13
    assert score["completeness"] == 20


def test_analyze_repo_url_aggregates_github_api_payloads(monkeypatch) -> None:
    calls: list[str] = []
    responses: dict[str, Any] = {
        "https://api.github.com/repos/owner/repo": {
            "full_name": "owner/repo",
            "description": "Repo",
            "stargazers_count": 12,
            "forks_count": 3,
            "subscribers_count": 2,
            "open_issues_count": 1,
            "language": "TypeScript",
            "pushed_at": "2026-05-24T00:00:00Z",
            "created_at": "2025-01-01T00:00:00Z",
            "license": {"spdx_id": "MIT"},
            "topics": "not-a-list",
        },
        "https://api.github.com/repos/owner/repo/languages": {"TypeScript": 1000},
        "https://api.github.com/repos/owner/repo/contributors?per_page=10": [{"login": "dev", "contributions": 5}],
        "https://api.github.com/repos/owner/repo/releases?per_page=5": [{"tag_name": "v1", "published_at": "2026-01-01"}],
    }

    class FakeGitHubClient(github_client_module.GitHubClient):
        def _get(self, url: str) -> Any:
            calls.append(url)
            return responses[url]

    signal = FakeGitHubClient().analyze_repo_url("https://github.com/owner/repo", source="test")

    assert signal is not None
    assert calls == list(responses)
    assert signal.full_name == "owner/repo"
    assert signal.language == "TypeScript"
    assert signal.license_spdx == "MIT"
    assert signal.topics == []
    assert signal.languages == {"TypeScript": 1000}
    assert signal.contributors == [{"login": "dev", "contributions": 5}]
    assert signal.releases == [{"tag_name": "v1", "published_at": "2026-01-01"}]
    assert signal.score > 0
