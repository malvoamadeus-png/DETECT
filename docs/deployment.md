# DETECT Deployment

## Current Split

- Frontend: GitHub + Vercel, read-only Supabase dashboard.
- Backend worker: long-lived Linux process, polls Bankr every 20 seconds.
- Database: Supabase Postgres, migrated from local using `SUPABASE_DB_URL`.

Run a local readiness check before deployment:

```powershell
cd D:\Coding\DETECT
.\scripts\check-deploy-ready.ps1
```

Run the local preflight suite before cutting a deployment:

```powershell
.\scripts\verify-local.ps1
```

Optional target checks:

```powershell
.\scripts\check-deploy-ready.ps1 -VercelBaseUrl https://<your-vercel-domain> -SshHost user@host
```

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
cp .env.example .env
nano .env
```

Fill `/opt/DETECT/.env` with the real values from the local project or secret manager. Do not paste secrets into shell history.

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
ExecStart=/opt/DETECT/.venv/bin/python /opt/DETECT/backend/src/main.py run-worker
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
bash scripts/linux/healthcheck-worker.sh
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

If the server does not have `/opt/DETECT/.env` yet and you have confirmed the target machine is correct:

```powershell
.\scripts\deploy-linux.ps1 -HostName user@host -UploadEnv -EnvPath .env
```

`-UploadEnv` copies the local `.env` to the server. Use it only for the intended production server.

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

The frontend reads `/api/dashboard`, and that server route queries `detect_dashboard` through `SUPABASE_DB_URL`. This keeps the browser read-only and avoids exposing DB credentials.

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

Important: the Vercel `NEXT_PUBLIC_SUPABASE_*` variables must belong to the same Supabase project as the worker's `SUPABASE_DB_URL`. If they point to different projects, the backend can write data successfully while the frontend still reports that `detect_dashboard` cannot be found in the schema cache.
