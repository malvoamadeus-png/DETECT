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
.\.venv\Scripts\python backend\src\main.py check-env
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

The frontend is a read-only dashboard. On Vercel, set the root directory to `frontend` and add `SUPABASE_DB_URL` so `/api/dashboard` reads the same database as the worker. `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are optional fallback variables.

Use Node 22 for the frontend build. The package engine range is `>=20.9.0`, matching Next 16's runtime requirement; CI currently builds with Node 22.

Before deploying on Vercel, copy `frontend/.env.production.example` to `frontend/.env.production.local`, fill `SUPABASE_DB_URL`, and verify it without printing secrets:

```powershell
.\scripts\check-vercel-env.ps1
```

## Linux Worker Deployment

```bash
cd /opt/DETECT
bash scripts/linux/bootstrap-server.sh
bash scripts/linux/install-worker.sh
sudo systemctl restart detect-worker.service
bash scripts/linux/preflight-worker.sh
bash scripts/linux/healthcheck-worker.sh
bash scripts/linux/logs-worker.sh
```

Create `/opt/DETECT/.env` from `.env.example` before starting the service. Do not commit the real `.env`.

From Windows, once SSH is available:

```powershell
.\scripts\deploy-linux.ps1 -HostName user@host
```

Linux worker deploys now default to the public HTTPS repo URL, so first-server bootstrap does not require a GitHub SSH key on the server.

Or run the final deployment orchestrator once both the worker host and public frontend URL are known:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -VercelBaseUrl https://your-vercel-domain
```

If Vercel CLI is installed, authenticated, and linked, the same orchestrator can also sync Vercel env and deploy the frontend:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -SyncVercelEnv -DeployVercel
```

If `SUPABASE_DB_URL` is configured directly in the Vercel dashboard instead of `frontend/.env.production.local`, add `-SkipVercelEnvCheck`.

Preview the generated remote deployment script without connecting:

```powershell
.\scripts\deploy-linux.ps1 -HostName user@host -DryRun
```

Preview the full orchestrator, including Vercel env/deploy intent, without changing external services:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -SyncVercelEnv -DeployVercel -DryRun
```

After Vercel deploys, verify the public app:

```powershell
.\scripts\smoke-vercel.ps1 -BaseUrl https://your-vercel-domain
```

After the Linux worker deploys, verify the remote service and require at least one dashboard row:

```powershell
.\scripts\smoke-linux-worker.ps1 -HostName user@host -MinimumRows 1
```

The smoke test waits up to 180 seconds by default so the worker has time to finish its first poll after a restart.

If Vercel CLI is installed and linked:

```powershell
.\scripts\deploy-vercel.ps1
```

If Vercel CLI is installed and linked, sync the required production database env from local `.env` without printing secrets:

```powershell
.\scripts\sync-vercel-env.ps1 -EnvPath .env
```

Check deployment readiness:

```powershell
.\scripts\check-deploy-ready.ps1
```

Use strict mode before production deployment:

```powershell
.\scripts\check-deploy-ready.ps1 -Strict -SkipGitHubActionsCheck -SkipVercelCliCheck
```

If GitHub does not create checks for a pushed commit, open the repository Actions tab and run the `CI` workflow manually. The workflow has a `workflow_dispatch` trigger for this fallback path.

With a token that has Actions write access, the same fallback can be triggered from PowerShell without printing the token:

```powershell
$env:GITHUB_TOKEN="..."
.\scripts\trigger-ci.ps1 -Wait
```

Check workflow visibility and whether the current branch head has a run, without a token:

```powershell
.\scripts\trigger-ci.ps1 -StatusOnly
```

Run the full local preflight:

```powershell
.\scripts\verify-local.ps1
```

## Supabase Env Alignment

`SUPABASE_DB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SUPABASE_URL`, and `NEXT_PUBLIC_SUPABASE_ANON_KEY` must point to the same Supabase project. If the backend migration succeeds but the frontend says `detect_dashboard` is missing from the schema cache, the usual cause is a DB URL for one project and an anon URL/key for another project.
