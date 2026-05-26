# DETECT Deployment Status

Last audited: 2026-05-26 Asia/Shanghai

## Proven Complete

- Code is pushed to GitHub remote `git@github.com:malvoamadeus-png/DETECT.git`.
- Latest runtime/code audit before this status note was commit `cea600d`.
- Local preflight passes for runtime-audited commit `cea600d`, including 29 backend tests, worker deploy dry-runs, CI checkout probe, backend environment check, tracked-file secret scan, frontend lint/typecheck, dashboard API limit checks, dashboard API error-response checks, server DB config checks, and frontend production build.
- Strict readiness passes for runtime-audited commit `cea600d` with GitHub Actions verified and Vercel CLI / real target checks intentionally skipped until external targets are available.
- GitHub Actions has `push`, `pull_request`, and `workflow_dispatch` triggers. The workflow has been hardened with explicit `contents: read` permission, manual HTTPS checkout, and Ubuntu-compatible PowerShell script calls.
- GitHub Actions is green for commit `cea600d`: `https://github.com/malvoamadeus-png/DETECT/actions/runs/26449695266`.
- Supabase migrations have been applied locally through the backend migration command.
- Supabase migration structure is covered by local preflight and CI wiring.
- Backend worker can run a real analysis pass and has produced dashboard rows in Supabase.
- Frontend lint, typecheck, dashboard API limit checks, public API error-response checks, server DB config checks, and production build succeed; the build includes `/api/dashboard` and `/api/health`.
- Frontend server API can read the same Postgres database through `SUPABASE_DB_URL`; the server-side Postgres client uses SSL plus explicit connection/query/statement timeouts.
- Vercel env template and preflight checker exist for `SUPABASE_DB_URL` without printing secrets.
- Current local env has usable `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `SUPABASE_DB_URL`. Public Supabase URL/key are present but appear to reference a different project from `SUPABASE_DB_URL`, so the first production frontend path should keep using `/api/dashboard` backed by `SUPABASE_DB_URL`.
- Tracked-file secret scan is part of local preflight and CI wiring.
- Local smoke test against the dashboard API has returned real data.
- Linux worker install, restart, health, log, and bootstrap scripts exist.
- Linux worker server-side preflight script exists for read-only diagnostics before/after install, accepts either `SUPABASE_DB_URL` or `DATABASE_URL`, and handles UTF-8 BOM env files.
- Windows helper scripts exist for Linux worker deploy, Vercel deploy, readiness checks, smoke tests, and local preflight.
- Readiness checks support strict production gating with explicit skips for known external constraints.
- Final deployment orchestrator exists for local preflight, readiness, worker deploy, and frontend smoke testing once external targets are known.
- Linux worker deploy dry-run and upload-env dry-run are covered by local verification and wired into GitHub Actions, including first-server bootstrap before clone and safe temp-file env upload before installing `/opt/DETECT/.env`.
- Backend unit tests cover Bankr launch parsing, X identity resolution priority/fallbacks, GitHub URL discovery/scoring/API aggregation, X cursor pagination, tweet dedupe, author filtering, 50-post defaults, configured target persistence, OpenAI analysis fallback behavior, and redacted environment diagnostics including X pagination env reporting.
- Frontend API limit checks cover `/api/dashboard?limit=` bounds for invalid, negative, decimal, default, and oversized values.
- Frontend API error checks ensure public `/api/dashboard` and `/api/health` responses do not expose internal exception messages.
- CI manual checkout is locally probed through HTTPS fetch of `refs/heads/main` and SHA comparison against the current local HEAD.
- Real `.env` remains ignored and is not committed.

## Current External Blockers

- Linux worker is not deployed to a real server because no SSH target has been provided.
- Vercel production is not verified because Vercel CLI is not installed locally and `frontend/.vercel/project.json` is not linked.
- Public deployed URL is not available yet, so production smoke test cannot be run.

## Required To Finish Deployment

1. Provide Linux SSH target, for example `user@host`.
2. Use default deployment path `/opt/DETECT` unless a different path is explicitly requested.
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
