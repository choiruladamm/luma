---
name: backend-deploy
description: Deploy the Luma Cloudflare Worker (apps/backend) to dev or prod, including D1 migrations and post-deploy verification. Run only when the user asks to deploy.
disable-model-invocation: true
argument-hint: dev|prod
---

# Deploy the backend Worker

Target env: `$ARGUMENTS` (`dev` or `prod`). No argument → ask. Run every command from the repo root.

## Preflight

1. `prod` only: the branch must be `master` with a clean tree (`make backend-deploy` refuses otherwise). Confirm with the user before deploying prod; it serves real users.
2. `make backend-test` exits 0.
3. Changed `wrangler.jsonc` → `make backend-types`, and commit the regenerated types.
4. New secret needed → confirm it exists: `cd apps/backend && bunx wrangler secret list --env <env>`. Missing → ask the user to set it with `bunx wrangler secret put <NAME> --env <env>`; never echo or write secret values.
5. Bundle size under 3 MB compressed: `cd apps/backend && bun run size`.

## Deploy

1. New files in `apps/backend/migrations/` → `make backend-migrate e=<env>` first. Migrations go before code that depends on them, and must keep existing data.
2. `make backend-deploy e=<env>`.
   - **First prod deploy** (the `luma-backend` Worker doesn't exist yet, so `wrangler secret put` can't run): deploy with the secrets file instead, from `master` in `apps/backend`: `bunx wrangler deploy --env prod --secrets-file ~/.config/luma/prod-secrets.json`. The file (outside the repo, mode 600) holds `BETTER_AUTH_SECRET`, `AI_KEY_ENC_SECRET`, `OPENROUTER_MANAGEMENT_KEY`, `GOOGLE_CLIENT_SECRET`. Never print it. Later deploys keep those secrets, so plain `make backend-deploy e=prod` is enough.
   - `AI_KEY_ENC_SECRET` must never change after the first prod deploy: stored AI keys can't be decrypted with a new one.

## Verify

1. `curl -s https://luma-api-dev.chrl.cloud/v1/health` (prod: `luma-api.chrl.cloud`) → `{"status":"ok","env":"<env>"}`. Cloudflare 1104/1042 right after a first deploy to a new domain clears within about a minute.
2. `dev`: `make backend-live` (Flutter client against the deployed Worker).
3. Touched an endpoint's cost → check CPU and errors in Workers Logs (`cd apps/backend && bunx wrangler tail --env <env>`), and confirm the budget table in `docs/backend.md` still holds.

## Report

State the env, the deployed version ID from the wrangler output, migrations applied (or none), and which verification steps passed.
