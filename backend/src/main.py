from __future__ import annotations

import argparse
from dataclasses import asdict
import base64
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from packages.common.env import load_project_env, read_sql
from packages.common.paths import ensure_data_dirs, get_paths
from packages.storage.repository import DetectRepository, postgres_connection
from packages.worker.service import run_once, run_worker


ENV_KEYS = [
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "OPENAI_MODEL",
    "SUPABASE_DB_URL",
    "DATABASE_URL",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "NEXT_PUBLIC_SUPABASE_URL",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    "DETECT_POLL_SECONDS",
    "DETECT_TARGET_TWEETS",
    "DETECT_MAX_X_PAGES",
]


def migrate() -> int:
    paths = ensure_data_dirs()
    migration_dir = paths.root / "supabase" / "migrations"
    sql_files = sorted(migration_dir.glob("*.sql"))
    if not sql_files:
        print("No migrations found.")
        return 0
    with postgres_connection() as conn:
        for path in sql_files:
            conn.execute(read_sql(path))
            print(f"migration=applied file={path.name}")
    return 0


def dashboard(limit: int) -> int:
    with postgres_connection() as conn:
        rows = DetectRepository(conn).list_dashboard(limit=limit)
    print(json.dumps(rows, ensure_ascii=False, indent=2))
    return 0


def _decode_jwt_payload(token: str) -> dict[str, object]:
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload.encode("utf-8")))
    except Exception:
        return {}


def _project_ref_from_url(value: str) -> str:
    if not value:
        return ""
    parsed = urlparse(value)
    host = parsed.hostname or ""
    if host.endswith(".supabase.co"):
        return host.split(".")[0]
    username = unquote(parsed.username or "")
    pieces = username.split(".")
    if len(pieces) > 1:
        return pieces[-1]
    return ""


def check_env() -> int:
    db_url = os.getenv("SUPABASE_DB_URL") or os.getenv("DATABASE_URL") or ""
    public_url = os.getenv("NEXT_PUBLIC_SUPABASE_URL") or os.getenv("SUPABASE_URL") or ""
    public_key = os.getenv("NEXT_PUBLIC_SUPABASE_ANON_KEY") or os.getenv("SUPABASE_ANON_KEY") or ""
    key_payload = _decode_jwt_payload(public_key)
    refs = {
        "db_url_project_ref": _project_ref_from_url(db_url),
        "public_url_project_ref": _project_ref_from_url(public_url),
        "anon_key_project_ref": str(key_payload.get("ref") or ""),
        "anon_key_role": str(key_payload.get("role") or ""),
    }
    statuses = {key: "set" if os.getenv(key) else "missing" for key in ENV_KEYS}
    public_mismatch = bool(
        refs["public_url_project_ref"] and refs["anon_key_project_ref"] and refs["public_url_project_ref"] != refs["anon_key_project_ref"]
    )
    db_public_mismatch = bool(
        refs["db_url_project_ref"] and refs["public_url_project_ref"] and refs["db_url_project_ref"] != refs["public_url_project_ref"]
    )
    print(
        json.dumps(
            {
                "env": statuses,
                "project_refs": refs,
                "public_supabase_mismatch": public_mismatch,
                "db_public_project_warning": db_public_mismatch,
                "note": "Values are redacted; this command does not print secrets.",
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    if statuses["OPENAI_API_KEY"] == "missing" or (statuses["SUPABASE_DB_URL"] == "missing" and statuses["DATABASE_URL"] == "missing"):
        return 1
    if public_mismatch:
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="DETECT backend")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("migrate", help="Apply Supabase/Postgres migrations.")

    once = subparsers.add_parser("run-once", help="Run one Bankr poll and analysis pass.")
    once.add_argument("--limit", type=int, default=None, help="Limit launches processed for this run.")

    subparsers.add_parser("run-worker", help="Run the long-lived 20 second polling worker.")

    dash = subparsers.add_parser("dashboard", help="Print dashboard rows from Supabase.")
    dash.add_argument("--limit", type=int, default=20)

    subparsers.add_parser("check-env", help="Print redacted deployment environment diagnostics.")
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    load_project_env()
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "migrate":
        return migrate()
    if args.command == "run-once":
        stats = run_once(limit=args.limit)
        print(json.dumps(asdict(stats), ensure_ascii=False, indent=2))
        return 0 if stats.errors == 0 else 1
    if args.command == "run-worker":
        run_worker()
        return 0
    if args.command == "dashboard":
        return dashboard(args.limit)
    if args.command == "check-env":
        return check_env()
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
