from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

from .paths import get_paths


def load_project_env() -> None:
    load_dotenv(get_paths().root / ".env", override=False)
    # Some Windows editors write a UTF-8 BOM before the first key; normalize it for os.environ callers.
    for key in list(os.environ):
        cleaned = key.lstrip("\ufeff")
        if cleaned != key and cleaned not in os.environ:
            os.environ[cleaned] = os.environ[key]


def env_str(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def env_int(name: str, default: int) -> int:
    raw = env_str(name, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def database_url() -> str:
    value = env_str("SUPABASE_DB_URL") or env_str("DATABASE_URL")
    if not value:
        raise RuntimeError("Missing SUPABASE_DB_URL or DATABASE_URL.")
    return value


def read_sql(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8")
