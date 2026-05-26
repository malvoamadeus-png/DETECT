from __future__ import annotations

import json
import os
import statistics
from typing import Any

import requests

from packages.common.models import AccountAssessment, GithubRepoSignal, LaunchRecord, XIdentity, XPost, XProfile


DEFAULT_SCORES = {
    "crypto_affinity": 0,
    "token_receptivity": 0,
    "builder_signal": 0,
    "open_source_footprint": 0,
    "social_leverage": 0,
    "risk": 50,
    "confidence": 35,
}


CRYPTO_TERMS = {
    "crypto",
    "token",
    "wallet",
    "solana",
    "ethereum",
    "base",
    "onchain",
    "trading",
    "defi",
    "airdrop",
    "swap",
    "staking",
    "contract",
    "bankr",
    "chain",
}
BUILDER_TERMS = {"build", "ship", "github", "repo", "rust", "python", "typescript", "agent", "api", "demo", "beta", "product"}


def interaction_summary(posts: list[XPost]) -> dict[str, float]:
    def median(values: list[int]) -> float:
        return float(statistics.median(values)) if values else 0.0

    return {
        "post_count": float(len(posts)),
        "median_likes": median([post.like_count for post in posts]),
        "median_reposts": median([post.repost_count for post in posts]),
        "median_replies": median([post.reply_count for post in posts]),
        "median_views": median([post.view_count for post in posts if post.view_count]),
    }


def heuristic_assessment(
    *,
    launch: LaunchRecord,
    identity: XIdentity | None,
    profile: XProfile | None,
    posts: list[XPost],
    github_repos: list[GithubRepoSignal],
) -> AccountAssessment:
    texts = " ".join([profile.description if profile else "", *[post.text for post in posts]]).lower()
    crypto_hits = sum(1 for term in CRYPTO_TERMS if term in texts)
    builder_hits = sum(1 for term in BUILDER_TERMS if term in texts)
    metrics = interaction_summary(posts)
    github_score = max([repo.score for repo in github_repos], default=0)
    scores = {
        "crypto_affinity": min(100, crypto_hits * 12 + (20 if launch.token_symbol else 0)),
        "token_receptivity": min(100, crypto_hits * 10 + (30 if "bankr" in texts or "$" + launch.token_symbol.lower() in texts else 0)),
        "builder_signal": min(100, builder_hits * 10 + (15 if profile and profile.website_url else 0)),
        "open_source_footprint": min(100, github_score),
        "social_leverage": min(100, int(metrics["median_likes"] * 1.2 + metrics["median_reposts"] * 4 + metrics["median_replies"] * 2)),
        "risk": 55,
        "confidence": min(85, 30 + len(posts) + (20 if profile else 0) + (10 if github_repos else 0)),
    }
    if scores["token_receptivity"] >= 70:
        verdict = "likely_accept"
    elif scores["token_receptivity"] >= 45:
        verdict = "likely_tolerate"
    elif scores["crypto_affinity"] < 20:
        verdict = "likely_reject"
    else:
        verdict = "unclear"
    archetype = "crypto_native_builder" if scores["crypto_affinity"] >= 65 and scores["builder_signal"] >= 50 else "unknown"
    if scores["crypto_affinity"] < 25 and scores["builder_signal"] >= 65:
        archetype = "general_tech_builder"
    elif scores["crypto_affinity"] >= 65 and scores["builder_signal"] < 40:
        archetype = "trader_or_kol"
    elif profile and profile.followers < 100 and len(posts) < 15:
        archetype = "project_account"
    summary = (
        f"Detected {archetype.replace('_', ' ')} with {scores['crypto_affinity']}/100 crypto affinity, "
        f"{scores['builder_signal']}/100 builder signal, and {scores['token_receptivity']}/100 token receptivity."
    )
    return AccountAssessment(
        archetype=archetype,
        verdict=verdict,
        summary=summary,
        scores=scores,
        reasons=[
            f"Collected {len(posts)} X posts toward the 50-post target.",
            f"Median engagement: {metrics['median_likes']:.0f} likes, {metrics['median_reposts']:.0f} reposts, {metrics['median_replies']:.0f} replies.",
            f"Best GitHub score: {github_score}/100." if github_repos else "No GitHub repository evidence was found.",
        ],
        risks=["Heuristic fallback was used because model analysis was unavailable."],
        evidence=[post.text[:220] for post in posts[:3]],
        model="heuristic",
        raw_payload={"metrics": metrics},
    )


def analyze_account(
    *,
    launch: LaunchRecord,
    identity: XIdentity | None,
    profile: XProfile | None,
    posts: list[XPost],
    github_repos: list[GithubRepoSignal],
) -> AccountAssessment:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    base_url = os.getenv("OPENAI_BASE_URL", "").strip().rstrip("/")
    model = os.getenv("OPENAI_MODEL", "gpt-5.4-mini").strip() or "gpt-5.4-mini"
    fallback = heuristic_assessment(
        launch=launch,
        identity=identity,
        profile=profile,
        posts=posts,
        github_repos=github_repos,
    )
    if not api_key or not base_url:
        return fallback
    payload = build_payload(launch, identity, profile, posts, github_repos)
    messages = [
        {
            "role": "system",
            "content": (
                "You evaluate whether an X account is likely to accept or tolerate a permissionless token launch "
                "where fees accrue to the recipient. Return strict JSON only."
            ),
        },
        {
            "role": "user",
            "content": json.dumps(payload, ensure_ascii=False),
        },
    ]
    schema_hint = {
        "archetype": "crypto_native_builder|ai_builder|trader_or_kol|project_account|general_tech_builder|non_crypto_public_figure|unknown",
        "verdict": "likely_accept|likely_tolerate|unclear|likely_reject",
        "summary": "One concise English paragraph.",
        "scores": DEFAULT_SCORES,
        "reasons": ["English evidence-based reason."],
        "risks": ["English risk or uncertainty."],
        "evidence": ["Short English evidence quote or paraphrase."],
    }
    messages.append({"role": "user", "content": "Use this JSON shape: " + json.dumps(schema_hint)})
    try:
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json={
                "model": model,
                "messages": messages,
                "temperature": 0.2,
                "response_format": {"type": "json_object"},
            },
            timeout=60,
        )
        response.raise_for_status()
        data = response.json()
        text = data["choices"][0]["message"]["content"]
        parsed = json.loads(text)
        scores = normalize_scores(parsed.get("scores") if isinstance(parsed.get("scores"), dict) else fallback.scores)
        return AccountAssessment(
            archetype=str(parsed.get("archetype") or fallback.archetype),
            verdict=str(parsed.get("verdict") or fallback.verdict),
            summary=str(parsed.get("summary") or fallback.summary),
            scores=scores,
            reasons=[str(item) for item in parsed.get("reasons", [])][:6] or fallback.reasons,
            risks=[str(item) for item in parsed.get("risks", [])][:6] or fallback.risks,
            evidence=[str(item) for item in parsed.get("evidence", [])][:6] or fallback.evidence,
            model=str(data.get("model") or model),
            raw_payload={"request": payload, "response": data},
        )
    except Exception as exc:
        return AccountAssessment(
            archetype=fallback.archetype,
            verdict=fallback.verdict,
            summary=fallback.summary,
            scores=fallback.scores,
            reasons=fallback.reasons,
            risks=[*fallback.risks, f"Model call failed: {exc}"],
            evidence=fallback.evidence,
            model=fallback.model,
            raw_payload=fallback.raw_payload,
        )


def normalize_scores(raw: dict[str, Any]) -> dict[str, int]:
    scores = dict(DEFAULT_SCORES)
    for key in scores:
        try:
            scores[key] = max(0, min(100, int(raw.get(key, scores[key]))))
        except Exception:
            pass
    return scores


def build_payload(
    launch: LaunchRecord,
    identity: XIdentity | None,
    profile: XProfile | None,
    posts: list[XPost],
    github_repos: list[GithubRepoSignal],
) -> dict[str, Any]:
    return {
        "launch": {
            "token_symbol": launch.token_symbol,
            "token_name": launch.token_name,
            "chain": launch.chain,
            "token_address": launch.token_address,
            "website_url": launch.website_url,
            "tweet_url": launch.tweet_url,
        },
        "identity": None
        if identity is None
        else {"username": identity.username, "source": identity.source, "confidence": identity.confidence},
        "profile": None
        if profile is None
        else {
            "username": profile.username,
            "display_name": profile.display_name,
            "description": profile.description,
            "followers": profile.followers,
            "following": profile.following,
            "statuses": profile.statuses,
            "website_url": profile.website_url,
        },
        "x_history": {
            "collected_count": len(posts),
            "interaction_summary": interaction_summary(posts),
            "posts": [
                {
                    "text": post.text[:800],
                    "likes": post.like_count,
                    "reposts": post.repost_count,
                    "replies": post.reply_count,
                    "views": post.view_count,
                    "created_at": post.created_at_raw,
                }
                for post in posts[:20]
            ],
        },
        "github": [
            {
                "source": repo.source,
                "full_name": repo.full_name,
                "description": repo.description,
                "stars": repo.stars,
                "forks": repo.forks,
                "language": repo.language,
                "pushed_at": repo.pushed_at,
                "license": repo.license_spdx,
                "score": repo.score,
                "score_breakdown": repo.score_breakdown,
            }
            for repo in github_repos
        ],
    }

