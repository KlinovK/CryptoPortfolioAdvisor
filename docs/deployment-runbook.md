# Deployment runbook

This is a vendor-neutral operator sequence for the current single-service MVP. Perform it in
staging first. Production repeats the same gates with separate credentials, database, hostname,
and iOS release configuration.

## Required operator inputs

- A host supporting Python 3.13, ASGI processes, injected secrets, HTTPS, log collection, health
  checks, and a daily scheduled command
- A dedicated PostgreSQL database and async-compatible `postgresql+psycopg://` URL
- A selected CoinGecko Demo or Pro plan/key with reviewed quota, license, and attribution terms
- An explicit OpenAI on/off decision; if on, an approved key, model, and reasoning effort
- A real HTTPS API hostname
- For App Store work: final bundle ID, Apple team/signing access, AppIcon, privacy-policy/support
  URLs, metadata, and a supported-device decision

## Staging

1. Provision a dedicated staging PostgreSQL database and save its URL in the host's secret store.
2. Configure this environment without committing its values:

   ```text
   APP_ENV=staging
   MARKET_DATA_MODE=live
   COINGECKO_API_TIER=demo|pro
   COINGECKO_API_KEY=<secret>
   OPENAI_ENABLED=false
   ANALYSIS_IDEMPOTENCY_MODE=database
   DATABASE_URL=postgresql+psycopg://<user>:<password>@<host>/<database>
   API_DOCS_ENABLED=false
   LOG_LEVEL=INFO
   ```

   If AI is approved, change `OPENAI_ENABLED=true` and inject `OPENAI_API_KEY`, `OPENAI_MODEL`,
   `OPENAI_REASONING_EFFORT`, timeout, and retry values. Never perform a live compatibility test
   merely because a key happens to exist; the test must also be authorized.
3. Install and migrate as a pre-deploy step. A nonzero migration exit stops the deployment:

   ```bash
   cd backend
   python -m pip install .
   alembic upgrade head
   ```

4. Start one worker using the host-provided port:

   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --workers 1
   ```

5. Configure liveness as `GET /health` and readiness as `GET /ready`. Verify through the public
   HTTPS hostname:

   ```bash
export API_BASE_URL='https://<actual-staging-hostname>'
   curl --fail-with-body --silent --show-error "$API_BASE_URL/health"
   curl --fail-with-body --silent --show-error "$API_BASE_URL/ready"
   ```

   Expected bodies are `{"status":"ok"}` and `{"status":"ready","database":"ok"}`.
6. With provider-call approval, submit the checked-in six-asset fixture once and retain the JSON
   and response headers:

   ```bash
   curl --fail-with-body --silent --show-error \
     --request POST "$API_BASE_URL/v1/portfolio/analyze" \
     --header 'Content-Type: application/json' \
     --header 'X-Request-ID: staging-phase12-first' \
     --data @deployment/staging-smoke-portfolio.json
   ```

   Validate current quotes, closed-candle features, response contract, analysis mode, warnings,
   and deterministic RiskEngine-filtered actions. When AI is enabled, also record the configured
   model, latency, token usage, and structured refusal/fallback result from sanitized logs.
7. Repeat the exact fixture. Confirm identical JSON, the same `analysis_id`, a `completed_hit`, and
   no second market/OpenAI execution.
8. Restart/redeploy the service, repeat again, and confirm the same stored result and no provider
   work. This is the deployed durable-retry gate.
9. Exercise unavailable/timeout/stale-provider and unavailable-database scenarios using the
   hosting platform's safe staging controls. Confirm the stable error envelope and absence of raw
   provider/database details. Confirm OpenAI outage/refusal becomes `ai_fallback` when enabled.
10. Configure a daily host job from `backend/`:

    ```bash
    python -m app.tools.cleanup_analysis_records
    ```

    Verify its JSON count enters normal logs and no scheduler is running inside the web process.
11. Check collected logs for request ID, snapshot ID, mode, idempotency outcome, provider/OpenAI
    outcome, latency, and token use. Search explicitly for keys, fixture holdings, prompts, raw
    candles, and raw payloads; none may appear.
12. Configure a Release-compatible iOS build with the real staging HTTPS base URL, install it on a
    signed physical iPhone, and run Dashboard → Analyze → Details → History → relaunch → retry.
    Also test offline/backend unavailable/timeout behavior and perform the VoiceOver pass.

Do not enable multiple workers until two real processes pass completed reuse, fingerprint conflict,
pending lease, worker termination, expired-lease takeover, and stale-owner non-overwrite tests.

## Production

1. Resolve every `BLOCKER` in [`release-checklist.md`](release-checklist.md). Use production-specific
   accounts and secrets; do not copy the staging database or keys blindly.
2. Reconfirm the CoinGecko plan/contract and any exact attribution implementation before building
   the release candidate.
3. Provision production PostgreSQL, inject `APP_ENV=production` plus the validated settings above,
   and run `alembic upgrade head`. Abort rollout on failure.
4. Start one worker, expose the real TLS hostname, and verify `/health`, `/ready`, certificate
   validity, logs, and cleanup scheduling.
5. Set the iOS Release `CPA_BACKEND_BASE_URL` to that exact HTTPS origin, final bundle identifier,
   team, version/build, signing, and complete AppIcon. Do not add ATS exceptions.
6. Run all repository gates, make a signed archive, validate it, install on a supported iPhone, and
   repeat the complete workflow and accessibility/network passes.
7. Submit one authorized production smoke request only if production test data is allowed. Reuse its
   snapshot UUID for the retry/restart check; do not leave repeated artificial analyses.
8. Complete App Store privacy answers from the deployed facts and public privacy policy. Archive
   the validation evidence, provider plan record, deployment revision, migration revision, and
   release checklist.

## Rollback and migration safety

Stop rollout when migration, readiness, TLS, or provider validation fails. Roll back application
code using the hosting platform while retaining the migrated database; the current migration is
additive and its downgrade drops durable results, so do not run `alembic downgrade` as an automatic
rollback. Investigate with sanitized operational metadata only.
