from __future__ import annotations

from typing import Any

from packages.launch_feed import client as launch_client


def _payload(activity_id: str = "activity-1") -> dict[str, Any]:
    return {
        "activityId": activity_id,
        "tokenName": "Detect Token",
        "tokenSymbol": "DTC",
        "chain": "base",
        "tokenAddress": "0x123",
        "launchType": "launch",
        "status": "created",
        "txHash": "0xabc",
        "poolId": "pool",
        "websiteUrl": "https://example.com",
        "tweetUrl": "https://x.com/bankr/status/1",
        "metadataUri": "ipfs://metadata",
        "imageUri": "ipfs://image",
        "timestamp": "1779790000000",
        "deployer": {"address": "0xdeployer"},
        "feeRecipient": {"address": "0xrecipient"},
    }


def test_parse_launch_accepts_string_timestamp_and_nested_people() -> None:
    launch = launch_client.parse_launch(_payload())

    assert launch is not None
    assert launch.activity_id == "activity-1"
    assert launch.token_symbol == "DTC"
    assert launch.timestamp_ms == 1779790000000
    assert launch.deployer == {"address": "0xdeployer"}
    assert launch.fee_recipient == {"address": "0xrecipient"}


def test_parse_launch_skips_missing_activity_id() -> None:
    payload = _payload("")

    assert launch_client.parse_launch(payload) is None


def test_fetch_latest_launches_accepts_common_list_keys(monkeypatch) -> None:
    payloads = [
        {"launches": [_payload("launches-1"), {"activityId": ""}]},
        {"data": [_payload("data-1")]},
        {"items": [_payload("items-1")]},
    ]

    for payload in payloads:
        monkeypatch.setattr(launch_client, "get_json", lambda url, payload=payload: payload)
        launches = launch_client.fetch_latest_launches()
        assert len(launches) == 1
        assert launches[0].activity_id.endswith("-1")


def test_fetch_latest_launches_returns_empty_for_unexpected_shape(monkeypatch) -> None:
    monkeypatch.setattr(launch_client, "get_json", lambda url: {"launches": {"bad": "shape"}})

    assert launch_client.fetch_latest_launches() == []
