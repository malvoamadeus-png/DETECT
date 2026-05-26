# DETECT Deployment

## Current Split

- Frontend: GitHub + Vercel, read-only Supabase dashboard.
- Backend worker: long-lived Linux process, polls Bankr every 20 seconds.
- Database: Supabase Postgres, migrated from local using `SUPABASE_DB_URL`.
- No auth, admin panel, or browser-side writes in the first version.

Run a local readiness check before deployment:

```powershell
cd D:\Coding\DETECT
.\scripts\check-deploy-ready.ps1
```

Run the local preflight suite before cutting a deployment:

```powershell
.\scripts\verify-local.ps1
```

If a push does not produce GitHub checks, open the repository Actions tab and manually run the `CI` workflow. The workflow includes `workflow_dispatch` for this fallback.

Check whether the workflow is active and whether the current branch head has an Actions run:

```powershell
.\scripts\trigger-ci.ps1 -StatusOnly
```

`-StatusOnly` uses `GITHUB_TOKEN` or `GH_TOKEN` when present; without a token, GitHub's anonymous API rate limit can prevent status polling, but the script reports that condition without printing secrets.

If you have a GitHub token with Actions write access:

```powershell
$env:GITHUB_TOKEN="..."
.\scripts\trigger-ci.ps1 -Wait
```

Optional target checks:

```powershell
.\scripts\check-deploy-ready.ps1 -VercelBaseUrl https://<your-vercel-domain> -SshHost user@host
```

Use `-Strict` for production gates. If GitHub checks are unavailable but local preflight has passed and you intentionally want to proceed, add `-SkipGitHubActionsCheck`. If Vercel is managed through the dashboard rather than local CLI, add `-SkipVercelCliCheck`.

The readiness check first tries the configured git remote, then falls back to the public GitHub branch API for `main` if SSH/GitHub networking is temporarily unreliable.

## Linux Worker

Suggested path:

```bash
/opt/DETECT
```

First-time checkout:

```bash
sudo mkdir -p /opt
sudo chown "$USER":"$USER" /opt
git clone git@github.com:malvoamadeus-png/DETECT.git /opt/DETECT
cd /opt/DETECT
bash scripts/linux/bootstrap-server.sh
cp .env.example .env
nano .env
```

Fill `/opt/DETECT/.env` with the real values from the local project or secret manager. Do not paste secrets into shell history.

The worker accepts either `SUPABASE_DB_URL` or `DATABASE_URL`; `SUPABASE_DB_URL` remains the preferred name because it makes the Vercel server route and worker config easier to compare.

Manual setup:

```bash
cd /opt/DETECT
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
python backend/src/main.py check-env
python backend/src/main.py migrate
python backend/src/main.py run-once --limit 3
```

Repeatable scripted setup/update:

```bash
cd /opt/DETECT
export DETECT_APP_DIR=/opt/DETECT
export DETECT_REPO_URL=git@github.com:malvoamadeus-png/DETECT.git
bash scripts/linux/install-worker.sh
sudo systemctl restart detect-worker.service
```

Long-running command:

```bash
cd /opt/DETECT
. .venv/bin/activate
python backend/src/main.py run-worker
```

## systemd Template

Create `/etc/systemd/system/detect-worker.service`:

```ini
[Unit]
Description=DETECT Bankr recipient intelligence worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/DETECT
EnvironmentFile=/opt/DETECT/.env
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/DETECT/.venv/bin/python -u /opt/DETECT/backend/src/main.py run-worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and inspect:

```bash
systemctl daemon-reload
systemctl enable --now detect-worker.service
systemctl status detect-worker.service
journalctl -u detect-worker.service -n 120 --no-pager
```

Scripted health check:

```bash
cd /opt/DETECT
bash scripts/linux/preflight-worker.sh
bash scripts/linux/healthcheck-worker.sh
```

Require at least one dashboard row during production validation:

```bash
cd /opt/DETECT
DETECT_HEALTH_MIN_DASHBOARD_ROWS=1 bash scripts/linux/healthcheck-worker.sh
```

Follow live worker logs:

```bash
cd /opt/DETECT
bash scripts/linux/logs-worker.sh
```

## Remote Deploy From Windows

After SSH access is ready, deploy from this local workspace:

```powershell
cd D:\Coding\DETECT
.\scripts\deploy-linux.ps1 -HostName user@host
```

By default this first bootstraps minimal packages before cloning the repo, then runs `scripts/linux/bootstrap-server.sh` after checkout. The bootstrap may use `sudo` to install `git`, `python3`, `python3-venv`, `python3-pip`, and CA certificates, and it verifies that both `python3 -m venv` and `python3 -m pip` work before continuing. Use `-SkipBootstrap` if the server is already prepared.

Preview the generated remote commands before connecting:

```powershell
.\scripts\deploy-linux.ps1 -HostName user@host -DryRun
```

Preview the full deployment orchestrator, including Vercel env/deploy intent, without changing external services:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -SyncVercelEnv -DeployVercel -DryRun
```

If the server does not have `/opt/DETECT/.env` yet and you have confirmed the target machine is correct:

```powershell
.\scripts\deploy-linux.ps1 -HostName user@host -UploadEnv -EnvPath .env
```

`-UploadEnv` copies the local `.env` to a temporary remote path, then installs it as `/opt/DETECT/.env` with mode `600` after the repo checkout/update step. Use it only for the intended production server.

After deploy, verify the remote worker over SSH and require at least one dashboard row:

```powershell
.\scripts\smoke-linux-worker.ps1 -HostName user@host -MinimumRows 1
```

The PowerShell smoke test waits up to 180 seconds by default so the worker has time to finish its first poll after a restart.

Once the worker host and public Vercel URL are both known, run the final orchestrator:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -VercelBaseUrl https://<your-vercel-domain>
```

This runs local preflight, readiness checks, optional Vercel env validation, Linux worker deploy, worker smoke testing, and frontend smoke testing. Use `-DryRun` to preview worker deployment, Vercel env sync, and Vercel deploy intent without changing external services.

If Vercel CLI is installed, authenticated, and linked to the project, the orchestrator can also sync production env and deploy the frontend:

```powershell
.\scripts\deploy-full.ps1 -SshHost user@host -SyncVercelEnv -DeployVercel
```

If `SUPABASE_DB_URL` was configured directly in the Vercel dashboard and no local `frontend/.env.production.local` exists, add `-SkipVercelEnvCheck`.

## Vercel

Project settings:

```text
Root Directory: frontend
Framework Preset: Next.js
Build Command: npm run build
Install Command: npm install
```

Recommended Vercel environment variable:

```text
SUPABASE_DB_URL
```

Local template/check:

```powershell
copy frontend\.env.production.example frontend\.env.production.local
.\scripts\check-vercel-env.ps1
```

If Vercel CLI is installed, authenticated, and linked to the `frontend` project, sync the production database env from the local `.env` without printing secrets:

```powershell
.\scripts\sync-vercel-env.ps1 -EnvPath .env
```

Preview which keys would be synced:

```powershell
.\scripts\sync-vercel-env.ps1 -EnvPath .env -DryRun
```

The frontend reads `/api/dashboard`, and that server route queries `detect_dashboard` through `SUPABASE_DB_URL`. This keeps the browser read-only and avoids exposing DB credentials. The server-side Postgres client uses SSL plus explicit connection/query/statement timeouts so Vercel functions fail fast instead of hanging on database connectivity issues. Public API responses use generic error messages while logging internal error details server-side for Vercel log inspection.

After deployment, open:

```text
https://<your-vercel-domain>/api/health
```

Expected shape:

```json
{"ok":true,"dashboard_rows":1}
```

Run the smoke test from Windows:

```powershell
cd D:\Coding\DETECT
.\scripts\smoke-vercel.ps1 -BaseUrl https://<your-vercel-domain>
```

If Vercel CLI is installed and this project has been linked locally:

```powershell
cd D:\Coding\DETECT
.\scripts\deploy-vercel.ps1
```

The script runs `vercel pull`, `vercel build --prod`, `vercel deploy --prebuilt --prod`, then runs the smoke test against the deployed URL.

Optional fallback variables:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

Use the fallback only when the public Supabase REST API points to the same project as the backend database.

Important: the Vercel `NEXT_PUBLIC_SUPABASE_*` variables must belong to the same Supabase project as the worker's `SUPABASE_DB_URL` if the public Supabase fallback is enabled. If they point to different projects, the backend can write data successfully while the frontend still reports that `detect_dashboard` cannot be found in the schema cache. The preferred first-version path is `/api/dashboard` backed by `SUPABASE_DB_URL`, which avoids relying on browser-side Supabase reads.
