from __future__ import annotations

import base64
import json

from src import main as backend_main


def _jwt_payload(payload: dict[str, object]) -> str:
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("ascii").rstrip("=")
    return f"header.{encoded}.signature"


def _clear_env(monkeypatch) -> None:
    for key in backend_main.ENV_KEYS:
        monkeypatch.delenv(key, raising=False)


def test_check_env_accepts_database_url_fallback(monkeypatch, capsys) -> None:
    _clear_env(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "x")
    monkeypatch.setenv("DATABASE_URL", "postgres://user.projref@host.example/db")

    exit_code = backend_main.check_env()
    output = capsys.readouterr().out
    payload = json.loads(output)

    assert exit_code == 0
    assert payload["env"]["SUPABASE_DB_URL"] == "missing"
    assert payload["env"]["DATABASE_URL"] == "set"
    assert payload["env"]["DETECT_MAX_X_PAGES"] == "missing"
    assert '"x"' not in output


def test_check_env_reports_x_pagination_setting(monkeypatch, capsys) -> None:
    _clear_env(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "x")
    monkeypatch.setenv("SUPABASE_DB_URL", "postgres://user.projref@host.example/db")
    monkeypatch.setenv("DETECT_MAX_X_PAGES", "8")

    exit_code = backend_main.check_env()
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["env"]["DETECT_MAX_X_PAGES"] == "set"


def test_check_env_fails_without_any_database_url(monkeypatch) -> None:
    _clear_env(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "x")

    assert backend_main.check_env() == 1


def test_check_env_fails_on_public_supabase_mismatch(monkeypatch, capsys) -> None:
    _clear_env(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "x")
    monkeypatch.setenv("SUPABASE_DB_URL", "postgres://user.dbref@host.example/db")
    monkeypatch.setenv("SUPABASE_URL", "https://publicref.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", _jwt_payload({"ref": "differentref", "role": "anon"}))

    exit_code = backend_main.check_env()
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 1
    assert payload["public_supabase_mismatch"] is True
    assert payload["project_refs"]["anon_key_role"] == "anon"
