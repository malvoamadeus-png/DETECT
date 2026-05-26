from __future__ import annotations

import re
from urllib.parse import urlparse

from packages.common.models import LaunchRecord, XIdentity
from packages.x_capture.client import FXTwitterClient, normalize_username


TWEET_ID_RE = re.compile(r"/status/(\d+)")
RESERVED = {"i", "home", "search", "explore", "messages", "notifications", "settings"}


def extract_x_username_from_url(url: str) -> str | None:
    if not url.strip():
        return None
    raw = url.strip()
    if "://" not in raw:
        raw = "https://" + raw.lstrip("/")
    parsed = urlparse(raw)
    if parsed.netloc.lower() not in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"}:
        return None
    parts = [part for part in parsed.path.split("/") if part]
    if not parts or parts[0].lower() in RESERVED:
        return None
    if len(parts) == 1:
        try:
            return normalize_username(parts[0])
        except ValueError:
            return None
    if len(parts) >= 2 and parts[1].lower() == "status":
        try:
            return normalize_username(parts[0])
        except ValueError:
            return None
    return None


def extract_tweet_id_from_url(url: str) -> str | None:
    if not url.strip():
        return None
    match = TWEET_ID_RE.search(url)
    return match.group(1) if match else None


def _identity(username: str, source: str, confidence: int, raw: dict | None = None) -> XIdentity | None:
    try:
        normalized = normalize_username(username)
    except ValueError:
        return None
    return XIdentity(
        username=normalized,
        source=source,
        profile_url=f"https://x.com/{normalized}",
        confidence=confidence,
        raw_payload=raw or {},
    )


def resolve_launch_identity(launch: LaunchRecord, client: FXTwitterClient | None = None) -> XIdentity | None:
    fee_username = str(launch.fee_recipient.get("xUsername") or "").strip()
    if fee_username:
        found = _identity(fee_username, "fee_recipient_x_username", 95, launch.fee_recipient)
        if found:
            return found

    deployer_username = str(launch.deployer.get("xUsername") or "").strip()
    if deployer_username:
        found = _identity(deployer_username, "deployer_x_username", 80, launch.deployer)
        if found:
            return found

    url_username = extract_x_username_from_url(launch.tweet_url)
    if url_username:
        return _identity(url_username, "tweet_url_profile", 70, {"tweetUrl": launch.tweet_url})

    tweet_id = extract_tweet_id_from_url(launch.tweet_url)
    if tweet_id:
        client = client or FXTwitterClient()
        detail = client.fetch_status_by_id(tweet_id)
        author = detail.get("author") if isinstance(detail.get("author"), dict) else {}
        author_username = str(author.get("screen_name") or "").strip()
        if author_username:
            return _identity(author_username, "tweet_url_status_author", 65, detail)
    return None

