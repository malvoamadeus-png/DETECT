from __future__ import annotations

import argparse
from dataclasses import asdict
import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from packages.common.env import load_project_env, read_sql
from packages.common.paths import ensure_data_dirs, get_paths
from packages.storage.repository import DetectRepository, postgres_connection
from packages.worker.service import run_once, run_worker


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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="DETECT backend")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("migrate", help="Apply Supabase/Postgres migrations.")

    once = subparsers.add_parser("run-once", help="Run one Bankr poll and analysis pass.")
    once.add_argument("--limit", type=int, default=None, help="Limit launches processed for this run.")

    subparsers.add_parser("run-worker", help="Run the long-lived 20 second polling worker.")

    dash = subparsers.add_parser("dashboard", help="Print dashboard rows from Supabase.")
    dash.add_argument("--limit", type=int, default=20)
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
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
