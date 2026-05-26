from __future__ import annotations

from typing import Any

from packages.x_capture import client as x_client_module
from packages.x_capture.client import FXTwitterClient


def _tweet(tweet_id: str, screen_name: str = "Target") -> dict[str, Any]:
    return {
        "id": tweet_id,
        "author": {
            "screen_name": screen_name,
            "name": screen_name,
            "followers": 123,
            "following": 10,
            "statuses": 456,
        },
        "text": f"tweet {tweet_id}",
        "created_timestamp": 1_700_000_000,
        "likes": 7,
        "reposts": 2,
        "replies": 1,
    }


def test_fetch_user_history_uses_bottom_cursor_filters_author_and_dedupes(monkeypatch) -> None:
    calls: list[dict[str, Any]] = []

    pages = [
        {
            "results": [
                _tweet("1"),
                _tweet("2", "OtherUser"),
                _tweet("1"),
                _tweet("3"),
            ],
            "cursor": {"bottom": "next-page"},
        },
        {
            "results": [_tweet("4"), _tweet("5")],
            "cursor": {},
        },
    ]

    def fake_get_json(url: str, *, params: dict[str, Any] | None = None, **_: Any) -> dict[str, Any]:
        calls.append({"url": url, "params": params or {}})
        return pages[len(calls) - 1]

    monkeypatch.setattr(x_client_module, "get_json", fake_get_json)

    profile, posts, meta = FXTwitterClient().fetch_user_history("Target", target_tweets=5, max_pages=3)

    assert profile is not None
    assert profile.username == "Target"
    assert [post.tweet_id for post in posts] == ["1", "3", "4", "5"]
    assert all(post.author_username.lower() == "target" for post in posts)
    assert len(calls) == 2
    assert calls[0]["params"] == {"count": 100}
    assert calls[1]["params"] == {"count": 100, "cursor": "next-page"}
    assert meta["target_reached"] is False
    assert meta["attempts"][0]["own_count"] == 2
    assert meta["attempts"][1]["own_count"] == 2


def test_fetch_user_history_stops_at_target_tweet_count(monkeypatch) -> None:
    calls = 0

    def fake_get_json(url: str, *, params: dict[str, Any] | None = None, **_: Any) -> dict[str, Any]:
        nonlocal calls
        calls += 1
        start = (calls - 1) * 20
        return {
            "results": [_tweet(str(start + offset)) for offset in range(20)],
            "cursor": {"bottom": f"cursor-{calls}"},
        }

    monkeypatch.setattr(x_client_module, "get_json", fake_get_json)

    _, posts, meta = FXTwitterClient().fetch_user_history("Target", target_tweets=50, max_pages=10)

    assert len(posts) == 50
    assert calls == 3
    assert meta["target_reached"] is True
    assert meta["attempts"][-1]["status"] == "target_reached"
