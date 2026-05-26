# DETECT Deployment Status

Last audited: 2026-05-26 Asia/Shanghai

## Proven Complete

- Code is pushed to GitHub remote `git@github.com:malvoamadeus-png/DETECT.git`.
- Local `main` and `origin/main` are aligned at `ff5e936`.
- Latest GitHub Actions CI for `ff5e936` completed successfully.
- Supabase migrations have been applied locally through the backend migration command.
- Backend worker can run a real analysis pass and has produced dashboard rows in Supabase.
- Frontend production build succeeds and includes `/api/dashboard` and `/api/health`.
- Frontend server API can read the same Postgres database through `SUPABASE_DB_URL`.
- Local smoke test against the dashboard API has returned real data.
- Linux worker install, restart, health, log, and bootstrap scripts exist.
- Windows helper scripts exist for Linux worker deploy, Vercel deploy, readiness checks, smoke tests, and local preflight.
- Real `.env` remains ignored and is not committed.

## Current External Blockers

- Linux worker is not deployed to a real server because no SSH target has been provided.
- Vercel production is not verified because Vercel CLI is not installed locally and `frontend/.vercel/project.json` is not linked.
- Public deployed URL is not available yet, so production smoke test cannot be run.

## Required To Finish Deployment

1. Provide Linux SSH target, for example `user@host`.
2. Confirm whether deployment path should be `/opt/DETECT`.
3. Either link Vercel locally or complete Vercel project binding in the dashboard.
4. Set Vercel production env `SUPABASE_DB_URL`.
5. Provide the deployed Vercel URL for smoke testing.

## Final Verification Commands

```powershell
.\scripts\verify-local.ps1
.\scripts\check-deploy-ready.ps1 -VercelBaseUrl https://<your-vercel-domain> -SshHost user@host
.\scripts\smoke-vercel.ps1 -BaseUrl https://<your-vercel-domain>
```

```bash
cd /opt/DETECT
bash scripts/linux/healthcheck-worker.sh
bash scripts/linux/logs-worker.sh
```
