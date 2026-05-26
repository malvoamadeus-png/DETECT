from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote, urlparse

from packages.common.http import get_json
from packages.common.models import XPost, XProfile


USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_]{1,15}$")
RESERVED_PATHS = {
    "home",
    "explore",
    "i",
    "search",
    "messages",
    "notifications",
    "settings",
    "tos",
    "privacy",
    "compose",
}


def normalize_username(value: str) -> str:
    raw = value.strip()
    if not raw:
        raise ValueError("username is empty")
    if raw.startswith("@"):
        raw = raw[1:]
    if "://" not in raw and "/" not in raw:
        username = raw
    else:
        if "://" not in raw:
            raw = "https://" + raw.lstrip("/")
        parsed = urlparse(raw)
        if parsed.netloc.lower() not in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"}:
            raise ValueError("profile URL must point to x.com or twitter.com")
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) != 1:
            raise ValueError("profile URL must be a direct user profile URL")
        username = parts[0].lstrip("@")
    if username.lower() in RESERVED_PATHS or not USERNAME_PATTERN.fullmatch(username):
        raise ValueError(f"invalid Twitter/X username: {username!r}")
    return username


def _int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _text(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        return str(value.get("text") or "").strip()
    return ""


def _media_urls(payload: dict[str, Any]) -> list[str]:
    media = payload.get("media")
    items: list[Any] = []
    if isinstance(media, dict) and isinstance(media.get("all"), list):
        items = media["all"]
    elif isinstance(media, list):
        items = media
    urls: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        url = str(item.get("url") or item.get("thumbnail_url") or "").strip()
        if url and url not in urls:
            urls.append(url)
    return urls


def post_from_fxtwitter(payload: dict[str, Any]) -> XPost | None:
    tweet_id = str(payload.get("id") or "").strip()
    author = payload.get("author") if isinstance(payload.get("author"), dict) else {}
    username = str(author.get("screen_name") or "").strip().lstrip("@")
    if not tweet_id or not username:
        return None
    return XPost(
        tweet_id=tweet_id,
        author_username=username,
        author_display_name=str(author.get("name") or username).strip(),
        url=str(payload.get("url") or f"https://x.com/{username}/status/{tweet_id}"),
        text=_text(payload.get("text") or payload.get("raw_text")),
        created_at_raw=str(payload.get("created_at") or "").strip(),
        created_timestamp=_int(payload.get("created_timestamp")) or None,
        reply_count=_int(payload.get("replies")),
        repost_count=_int(payload.get("reposts") or payload.get("retweets")),
        like_count=_int(payload.get("likes")),
        bookmark_count=_int(payload.get("bookmarks")),
        view_count=_int(payload.get("views")),
        media_urls=_media_urls(payload),
        raw_payload=payload,
    )


def profile_from_author(author: dict[str, Any], username: str) -> XProfile:
    website = author.get("website") if isinstance(author.get("website"), dict) else {}
    return XProfile(
        username=str(author.get("screen_name") or username).strip().lstrip("@") or username,
        display_name=str(author.get("name") or username).strip(),
        description=str(author.get("description") or "").strip(),
        followers=_int(author.get("followers")),
        following=_int(author.get("following")),
        statuses=_int(author.get("statuses")),
        website_url=str(website.get("url") or "").strip(),
        avatar_url=str(author.get("avatar_url") or "").strip(),
        banner_url=str(author.get("banner_url") or "").strip(),
        joined=str(author.get("joined") or "").strip(),
        raw_payload=author,
    )


class FXTwitterClient:
    def fetch_status_by_id(self, tweet_id: str) -> dict[str, Any]:
        payload = get_json(f"https://api.fxtwitter.com/i/status/{tweet_id}")
        tweet = payload.get("tweet")
        return tweet if isinstance(tweet, dict) else {}

    def fetch_tweet_detail(self, username: str, tweet_id: str) -> dict[str, Any]:
        normalized = normalize_username(username)
        payload = get_json(f"https://api.fxtwitter.com/{normalized}/status/{tweet_id}")
        tweet = payload.get("tweet")
        return tweet if isinstance(tweet, dict) else {}

    def fetch_user_history(
        self,
        username: str,
        *,
        target_tweets: int = 50,
        max_pages: int = 10,
    ) -> tuple[XProfile | None, list[XPost], dict[str, Any]]:
        normalized = normalize_username(username)
        seen: set[str] = set()
        posts: list[XPost] = []
        profile: XProfile | None = None
        cursor: str | None = None
        attempts: list[dict[str, Any]] = []
        for page in range(1, max(1, max_pages) + 1):
            params = {"count": 100}
            if cursor:
                params["cursor"] = quote(cursor, safe="")
            url = f"https://api.fxtwitter.com/2/profile/{normalized}/statuses"
            try:
                payload = get_json(url, params=params)
            except Exception as exc:
                attempts.append({"page": page, "status": "fetch_failed", "error": str(exc)})
                break
            results = payload.get("results")
            if not isinstance(results, list) or not results:
                attempts.append({"page": page, "status": "empty", "count": 0})
                break
            own_count = 0
            for item in results:
                if not isinstance(item, dict):
                    continue
                author = item.get("author") if isinstance(item.get("author"), dict) else {}
                if str(author.get("screen_name") or "").lower() != normalized.lower():
                    continue
                if profile is None:
                    profile = profile_from_author(author, normalized)
                post = post_from_fxtwitter(item)
                if not post or post.tweet_id in seen:
                    continue
                seen.add(post.tweet_id)
                posts.append(post)
                own_count += 1
                if len(posts) >= target_tweets:
                    attempts.append({"page": page, "status": "target_reached", "raw_count": len(results), "own_count": own_count})
                    return profile, posts, {"attempts": attempts, "target_reached": True}
            attempts.append({"page": page, "status": "ok", "raw_count": len(results), "own_count": own_count})
            cursor_payload = payload.get("cursor") if isinstance(payload.get("cursor"), dict) else {}
            cursor = str(cursor_payload.get("bottom") or "").strip() or None
            if not cursor:
                break
        return profile, posts, {"attempts": attempts, "target_reached": len(posts) >= target_tweets}

