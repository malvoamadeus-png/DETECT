# DETECT

DETECT watches Bankr token launches, resolves fee-recipient X accounts, collects recent X history, discovers GitHub signals, and produces an English account assessment for a public dashboard.

## Tree

```text
DETECT/
  backend/
    packages/
      account_analyzer/
      common/
      github_analyzer/
      launch_feed/
      storage/
      worker/
      x_capture/
      x_resolver/
    src/
      main.py
    requirements.txt
  frontend/
    src/
      app/
      lib/
      types/
    package.json
  data/
    raw/
    processed/
    exports/
  supabase/
    migrations/
  docs/
```

## Local Backend

```powershell
cd D:\Coding\DETECT
python -m venv .venv
.\.venv\Scripts\pip install -r backend\requirements.txt
.\.venv\Scripts\python backend\src\main.py migrate
.\.venv\Scripts\python backend\src\main.py run-once --limit 5
.\.venv\Scripts\python backend\src\main.py run-worker
```

## Local Frontend

```powershell
cd D:\Coding\DETECT
npm.cmd --prefix frontend install
.\scripts\run-frontend.ps1
```

The frontend is a read-only dashboard. Vercel needs `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

## Supabase Env Alignment

`SUPABASE_DB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SUPABASE_URL`, and `NEXT_PUBLIC_SUPABASE_ANON_KEY` must point to the same Supabase project. If the backend migration succeeds but the frontend says `detect_dashboard` is missing from the schema cache, the usual cause is a DB URL for one project and an anon URL/key for another project.
