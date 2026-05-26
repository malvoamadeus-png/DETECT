from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal


Stage = Literal[
    "discovered",
    "identity_resolved",
    "x_fetching",
    "x_fetched",
    "github_scanning",
    "github_scanned",
    "ai_analyzing",
    "completed",
    "failed",
]


@dataclass(frozen=True, slots=True)
class LaunchRecord:
    activity_id: str
    token_name: str
    token_symbol: str
    chain: str
    token_address: str
    launch_type: str
    status: str
    tx_hash: str
    pool_id: str
    website_url: str
    tweet_url: str
    metadata_uri: str
    image_uri: str
    timestamp_ms: int | None
    deployer: dict[str, Any] = field(default_factory=dict)
    fee_recipient: dict[str, Any] = field(default_factory=dict)
    raw_payload: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class XIdentity:
    username: str
    source: str
    profile_url: str
    confidence: int
    raw_payload: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class XPost:
    tweet_id: str
    author_username: str
    author_display_name: str
    url: str
    text: str
    created_at_raw: str
    created_timestamp: int | None
    reply_count: int
    repost_count: int
    like_count: int
    bookmark_count: int
    view_count: int
    media_urls: list[str]
    raw_payload: dict[str, Any]


@dataclass(frozen=True, slots=True)
class XProfile:
    username: str
    display_name: str
    description: str
    followers: int
    following: int
    statuses: int
    website_url: str
    avatar_url: str
    banner_url: str
    joined: str
    raw_payload: dict[str, Any]


@dataclass(frozen=True, slots=True)
class GithubRepoSignal:
    owner: str
    repo: str
    canonical_url: str
    source: str
    full_name: str = ""
    description: str = ""
    stars: int = 0
    forks: int = 0
    subscribers: int = 0
    open_issues: int = 0
    language: str = ""
    pushed_at: str = ""
    created_at: str = ""
    license_spdx: str = ""
    topics: list[str] = field(default_factory=list)
    languages: dict[str, int] = field(default_factory=dict)
    contributors: list[dict[str, Any]] = field(default_factory=list)
    releases: list[dict[str, Any]] = field(default_factory=list)
    score: int = 0
    score_breakdown: dict[str, int] = field(default_factory=dict)
    raw_payload: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class AccountAssessment:
    archetype: str
    verdict: str
    summary: str
    scores: dict[str, int]
    reasons: list[str]
    risks: list[str]
    evidence: list[str]
    model: str
    raw_payload: dict[str, Any]

