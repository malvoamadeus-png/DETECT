from __future__ import annotations

from typing import Any

from packages.common.models import LaunchRecord
from packages.x_resolver import resolver


def _launch(**overrides: Any) -> LaunchRecord:
    values = {
        "activity_id": "launch-1",
        "token_name": "Token",
        "token_symbol": "TOK",
        "chain": "base",
        "token_address": "0x123",
        "launch_type": "launch",
        "status": "created",
        "tx_hash": "0xabc",
        "pool_id": "",
        "website_url": "",
        "tweet_url": "",
        "metadata_uri": "",
        "image_uri": "",
        "timestamp_ms": None,
        "deployer": {},
        "fee_recipient": {},
        "raw_payload": {},
    }
    values.update(overrides)
    return LaunchRecord(**values)


class FakeFXTwitterClient:
    def __init__(self, detail: dict[str, Any]) -> None:
        self.detail = detail
        self.status_ids: list[str] = []

    def fetch_status_by_id(self, tweet_id: str) -> dict[str, Any]:
        self.status_ids.append(tweet_id)
        return self.detail


def test_extract_x_username_from_profile_and_status_urls() -> None:
    assert resolver.extract_x_username_from_url("x.com/Builder") == "Builder"
    assert resolver.extract_x_username_from_url("https://twitter.com/Builder/status/123?s=20") == "Builder"
    assert resolver.extract_x_username_from_url("https://x.com/search?q=Builder") is None
    assert resolver.extract_x_username_from_url("https://example.com/Builder") is None


def test_extract_tweet_id_from_standard_and_i_status_urls() -> None:
    assert resolver.extract_tweet_id_from_url("https://x.com/Builder/status/123/photo/1") == "123"
    assert resolver.extract_tweet_id_from_url("https://x.com/i/status/456") == "456"
    assert resolver.extract_tweet_id_from_url("https://x.com/Builder") is None


def test_resolve_prefers_fee_recipient_over_deployer_and_tweet_url() -> None:
    identity = resolver.resolve_launch_identity(
        _launch(
            fee_recipient={"xUsername": "@FeeUser"},
            deployer={"xUsername": "DeployUser"},
            tweet_url="https://x.com/TweetUser/status/123",
        )
    )

    assert identity is not None
    assert identity.username == "FeeUser"
    assert identity.source == "fee_recipient_x_username"
    assert identity.confidence == 95


def test_resolve_falls_back_to_deployer_username() -> None:
    identity = resolver.resolve_launch_identity(_launch(deployer={"xUsername": "DeployUser"}))

    assert identity is not None
    assert identity.username == "DeployUser"
    assert identity.source == "deployer_x_username"


def test_resolve_uses_tweet_url_profile_or_status_path() -> None:
    identity = resolver.resolve_launch_identity(_launch(tweet_url="https://twitter.com/TweetUser/status/123"))

    assert identity is not None
    assert identity.username == "TweetUser"
    assert identity.source == "tweet_url_profile"


def test_resolve_uses_fxtwitter_detail_for_i_status_url() -> None:
    client = FakeFXTwitterClient({"author": {"screen_name": "AuthorUser"}})
    identity = resolver.resolve_launch_identity(_launch(tweet_url="https://x.com/i/status/456"), client=client)

    assert identity is not None
    assert identity.username == "AuthorUser"
    assert identity.source == "tweet_url_status_author"
    assert client.status_ids == ["456"]


def test_resolve_returns_none_for_unusable_inputs() -> None:
    assert resolver.resolve_launch_identity(_launch(tweet_url="https://example.com/nope")) is None
    assert resolver.resolve_launch_identity(_launch(fee_recipient={"xUsername": "invalid/user"})) is None
