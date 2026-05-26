from __future__ import annotations

from typing import Any

import requests


DEFAULT_TIMEOUT = 25
USER_AGENT = "detect-token-intel/0.1"


def get_json(url: str, *, params: dict[str, Any] | None = None, timeout: int = DEFAULT_TIMEOUT) -> dict[str, Any]:
    response = requests.get(
        url,
        params=params,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json,text/plain,*/*",
            "Accept-Encoding": "gzip, deflate",
        },
        timeout=timeout,
    )
    if response.status_code == 204:
        return {}
    response.raise_for_status()
    payload = response.json()
    return payload if isinstance(payload, dict) else {}

