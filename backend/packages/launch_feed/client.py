from __future__ import annotations

from typing import Any

from packages.common.http import get_json
from packages.common.models import LaunchRecord


BANKR_LAUNCHES_URL = "https://api.bankr.bot/token-launches"


def _str(payload: dict[str, Any], key: str) -> str:
    return str(payload.get(key) or "").strip()


def _person(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    return value if isinstance(value, dict) else {}


def _int_or_none(value: Any) -> int | None:
    try:
        if isinstance(value, bool) or value is None or value == "":
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def parse_launch(payload: dict[str, Any]) -> LaunchRecord | None:
    activity_id = _str(payload, "activityId")
    if not activity_id:
        return None
    timestamp = payload.get("timestamp")
    return LaunchRecord(
        activity_id=activity_id,
        token_name=_str(payload, "tokenName"),
        token_symbol=_str(payload, "tokenSymbol"),
        chain=_str(payload, "chain"),
        token_address=_str(payload, "tokenAddress"),
        launch_type=_str(payload, "launchType"),
        status=_str(payload, "status"),
        tx_hash=_str(payload, "txHash"),
        pool_id=_str(payload, "poolId"),
        website_url=_str(payload, "websiteUrl"),
        tweet_url=_str(payload, "tweetUrl"),
        metadata_uri=_str(payload, "metadataUri"),
        image_uri=_str(payload, "imageUri"),
        timestamp_ms=_int_or_none(timestamp),
        deployer=_person(payload, "deployer"),
        fee_recipient=_person(payload, "feeRecipient"),
        raw_payload=payload,
    )


def fetch_latest_launches() -> list[LaunchRecord]:
    payload = get_json(BANKR_LAUNCHES_URL)
    launches = payload.get("launches") or payload.get("data") or payload.get("items")
    if not isinstance(launches, list):
        return []
    parsed: list[LaunchRecord] = []
    for item in launches:
        if isinstance(item, dict):
            launch = parse_launch(item)
            if launch:
                parsed.append(launch)
    return parsed
