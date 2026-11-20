#!/usr/bin/env bash
# E2E sync push and pull: a local Worker (wrangler dev, local D1/R2) driven by the Dart sync tests.
# Run from the repo root with `make backend-e2e`.
set -euo pipefail

port=8788
backend="$(cd "$(dirname "$0")/.." && pwd)"
app="$backend/../mobile"
code="LUMA-E2E$(date +%s)"
code2="LUMA-E2F$(date +%s)"
log="$(mktemp -t luma-e2e)"

cd "$backend"
bunx wrangler d1 migrations apply DB --env dev --local >/dev/null
bunx wrangler d1 execute DB --env dev --local \
  --command "INSERT INTO invite_codes (code, created_at) VALUES ('$code', $(date +%s)000), ('$code2', $(date +%s)000)" >/dev/null

bunx wrangler dev --env dev --port "$port" >"$log" 2>&1 &
worker=$!
trap 'kill $worker 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  curl -sf "http://127.0.0.1:$port/v2/health" >/dev/null && break
  sleep 1
done
curl -sf "http://127.0.0.1:$port/v2/health" >/dev/null || { cat "$log"; exit 1; }

cd "$app"
LUMA_BACKEND_E2E="http://127.0.0.1:$port" LUMA_E2E_INVITE="$code" LUMA_E2E_INVITE2="$code2" \
  fvm flutter test --timeout 120s test/data/sync_e2e_test.dart
