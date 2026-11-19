---
type: how-to
purpose: Provision the Cloudflare, Google, and OpenRouter resources for the mobile API and admin dashboard.
sections: [D1 and R2, Google OAuth clients, OpenRouter workspaces, Dashboard Access and custom domains, Secrets and first launch, GitHub deploy pipeline]
---

# Provision Luma services

Use this guide for one-time setup. Routine deploys run in GitHub Actions (see [GitHub deploy pipeline](#github-deploy-pipeline)); for a manual deploy, use the [backend-deploy skill](../.claude/skills/backend-deploy/SKILL.md).

## D1 and R2

1. From the repo root, run `make backend-install` and `make dashboard-install`. Sign Wrangler into the intended Cloudflare account and enable R2 there.
2. Create the resources shown in [Environments and bindings](backend.md#environments-and-bindings). For example, from `apps/backend` for dev:

   ```sh
   bunx wrangler login
   bunx wrangler d1 create luma-dev
   bunx wrangler r2 bucket create luma-dev
   ```

3. In both apps' `wrangler.jsonc`, use the returned D1 database ID and name for `DB` in the matching environment. Keep each environment's private bucket bound to the backend as `BUCKET`. Run `make backend-types` from the repo root after editing the backend bindings.
4. Before the first launch, run `make backend-migrate e=<env>` from the repo root. The dashboard uses that same database and migration set. [D1 setup](https://developers.cloudflare.com/d1/get-started/) · [R2 Worker bindings](https://developers.cloudflare.com/r2/api/workers/workers-api-usage/)

## Google OAuth clients

1. In the Google Cloud project, configure the OAuth consent screen. If its publishing status is Testing, add the mobile testers and dashboard admins to the test-user list.
2. Create a **Web application** OAuth client. Use its ID as the mobile `serverClientId` in `googleClients` and as the first entry of each backend `GOOGLE_CLIENT_IDS` list. Set the dashboard's `GOOGLE_CLIENT_ID` to that same web ID.
3. Add these authorized redirect URIs to the web client for dashboard sign-in. Mobile sign-in supplies an ID token directly.

   - `https://luma-admin-dev.chrl.cloud/api/auth/callback/google`
   - `https://luma-admin.chrl.cloud/api/auth/callback/google`
   - `http://localhost:5173/api/auth/callback/google`

4. Create an **iOS** OAuth client for each bundle ID (`id.ruma.luma.dev`, `id.ruma.luma`). Set its ID in `googleClients` in `apps/mobile/lib/data/services/google_auth.dart` and its reversed ID in the matching Xcode `GOOGLE_REVERSED_CLIENT_ID` build settings.
5. Create an **Android** OAuth client for each package and signing certificate SHA-1 used by that environment. Register debug and release certificates for dev and the production release certificate for prod. A prod debug build needs its own registered certificate to sign in.
6. Add the platform client IDs to the matching backend `GOOGLE_CLIENT_IDS` comma-separated list and save the web client secret for the Worker secrets step. [Google web OAuth](https://developers.google.com/identity/protocols/oauth2/web-server) · [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating) · [Google Sign-In for Android](https://developers.google.com/identity/sign-in/android/legacy-gsi-start)

## OpenRouter workspaces

1. In OpenRouter, create separate subsidy workspaces for dev and prod. Set each workspace ID as `OPENROUTER_WORKSPACE_ID` in the backend environment. The dashboard build reads the workspace ID and display budget from the matching backend configuration.
2. In each workspace's default guardrail, set the allowlist to the union of `AI_CHAT_MODELS` and `AI_EMBEDDING_MODELS`. Configure the pooled monthly cap in Workspace Budgets and set `AI_MONTHLY_BUDGET_USD` to the same display value. The default guardrail’s budget applies per member or API key. [OpenRouter spend controls](https://openrouter.ai/docs/guides/best-practices/spend-controls)
3. Create a workspace-scoped management API key for each environment and grant it `activity:view_all` for the dashboard’s activity query. Use it for key creation, usage reads, and revocation in the backend, and for activity and key management calls in the dashboard. Save it as `OPENROUTER_MANAGEMENT_KEY` in each Worker. [OpenRouter API key management](https://openrouter.ai/docs/guides/overview/auth/management-api-keys)

## Dashboard Access and custom domains

1. Use the Cloudflare-managed `chrl.cloud` zone. Keep the API custom domain routes from [Environments and bindings](backend.md#environments-and-bindings) and the dashboard custom domains from `apps/dashboard/wrangler.jsonc`. Set each Worker's `BETTER_AUTH_URL` to its HTTPS origin. Wrangler custom domain routes provision the DNS records and TLS certificates. [Workers Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
2. Before attaching the dashboard custom domains, create a self-hosted Cloudflare Access application for each hostname, `luma-admin-dev.chrl.cloud` and `luma-admin.chrl.cloud`. Leave the path blank to cover the whole host. Select One-time PIN, add an Allow policy for the admin email addresses, and set the application session duration to one month (720 hours). Keep `workers_dev` and `preview_urls` disabled for the dashboard. [Cloudflare Access for public hostnames](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/)
3. Set `ADMIN_EMAILS` in each dashboard environment to the comma-separated Google admin addresses. The first successful sign-in can create a verified admin's user and linked provider account in the shared D1 database.
4. To reproduce the Access branding, upload [the Luma logo](../apps/dashboard/brand/luma-logo.svg) to the separate public `luma-brand` R2 bucket at `https://luma-brand.chrl.cloud/luma-logo.svg`. Connect the custom domain and disable the public `r2.dev` URL. In Zero Trust custom pages, set the organization name to Luma, background to `#F2EDDD`, text to `#1A1A1A`, set the footer to `Khusus admin Luma`, and use the logo URL. [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)

## Secrets and first launch

Set secrets per environment. From the corresponding app directory, run `bunx wrangler secret put <NAME> --env <env>` for an existing Worker. For first deployment with a secrets file, keep it outside the repo with restricted permissions and use the first-deploy procedure in the [backend-deploy skill](../.claude/skills/backend-deploy/SKILL.md). Keep secret values out of Wrangler config.

| Worker | Secrets |
|---|---|
| Backend | `BETTER_AUTH_SECRET`, `GOOGLE_CLIENT_SECRET`, `OPENROUTER_MANAGEMENT_KEY`, `AI_KEY_ENC_SECRET` |
| Dashboard | Its own `BETTER_AUTH_SECRET`, `GOOGLE_CLIENT_SECRET`, `OPENROUTER_MANAGEMENT_KEY` |

Generate independent auth secrets and a backend encryption secret with `openssl rand -base64 32`. Preserve `AI_KEY_ENC_SECRET` across deployments so stored subsidy keys stay decryptable. For local development, copy each app's `.dev.vars.example` to its gitignored `.dev.vars` and set the local dashboard admin list and auth URL there.

1. Deploy and verify the backend using the linked skill.
2. Once Access and the shared D1 database are ready, deploy the dashboard with `make dashboard-deploy e=<env>`. To supply a secrets file on the first dashboard deploy, run the Make target's Vite build and pass `--secrets-file <path>` to the ensuing Wrangler deploy so it uses the generated config. Follow the same production branch requirement as the Make target.
3. Open the dashboard in an unauthenticated browser. Expect the Access login before the app renders. After passing Access, the dashboard session endpoint returns `null` until you sign in with Google. Verify that a configured admin can reach Overview and that it shows data from the matching D1 environment.

## GitHub deploy pipeline

`.github/workflows/deploy.yml` runs on every push to `dev` (env `dev`) and `master` (env `prod`): `make dashboard-build` (so a build failure stops the run before anything remote changes), `make backend-migrate`, `make backend-deploy`, `make dashboard-deploy`, then a `/v1/health` check against the matching API domain. Pushes reach those branches only through PRs, and `ci.yml` runs on PRs only. After a push to `master` that carries changes `dev` lacks (a hotfix PR), the `back-merge` job pushes a `backmerge/master-<sha>` branch, opens a PR into `dev`, and dispatches CI on it. A merge conflict fails that job; merge `master` into `dev` by hand.

1. In Cloudflare, create an API token from the **Edit Cloudflare Workers** template, add **Account · D1 · Edit**, and limit it to the Luma account and the `chrl.cloud` zone. [Cloudflare API tokens](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
2. In GitHub **Settings → Environments**, create `dev` and `prod`. Give each the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, and limit deployment branches to `dev` and `master` respectively.
3. Create `dev` from `master` and make it the default branch, so PRs target it.
4. Add a branch ruleset each for `dev` and `master`: require a PR merged with a merge commit, require the status checks `hygiene`, `mobile-test`, `backend-test`, and `dashboard-test`, block force pushes and deletion, and allow no bypass. Only `dev` requires branches to be up to date before merging: after each release `master` holds a merge commit that `dev` lacks, and updating a release PR's head would push to `dev` directly.
5. In **Settings → Actions → General**, enable **Allow GitHub Actions to create and approve pull requests** so the back-merge job can open its PR. Keep merge commits enabled in **Settings → General**.
