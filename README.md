# CryptoPortfolioAdvisor

CryptoPortfolioAdvisor is a production-oriented iOS app and Python service for analyzing a
manually entered cryptocurrency portfolio. It returns structured daily recommendations under
the user's constraints. It never connects to an exchange and never executes a trade.

## Repository structure

- `ios/` — Swift 6, SwiftUI, TCA, URLSession, and local SwiftData history.
- `backend/` — FastAPI orchestration, deterministic calculation/risk rules, optional OpenAI
  reasoning, live/static market adapters, and durable production idempotency.
- `contracts/` — the stable platform-neutral `PortfolioAnalysis` JSON contract.
- `docs/` — architecture, API, deployment runbook, privacy data flow, and release documentation.
- `AGENTS.md` — scope and architecture rules for future work.

## Prerequisites and local development

- Python 3.13
- Xcode with Swift 6 and an iOS 18-or-later SDK
- PostgreSQL for production; local/default tests use in-memory coordination or temporary SQLite

Install and verify the backend:

```bash
cd backend
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
pytest
ruff check .
ruff format --check .
pip check
```

Run the local static service with `uvicorn app.main:app --reload`. The iOS Debug build uses
`http://127.0.0.1:8000`; its Release build reads one HTTPS-only build setting and rejects local
hosts. Replace the reserved `https://api.example.com` Release placeholder before distribution.
See [`docs/deployment.md`](docs/deployment.md) and the staging-first
[`docs/deployment-runbook.md`](docs/deployment-runbook.md) for migrations, runtime configuration,
and deployment validation.

## System boundary

iOS saves an immutable snapshot locally, sends it to `POST /v1/portfolio/analyze`, validates the
response, and saves one immutable analysis for History. Financial numbers are decimal strings on
the wire and become Foundation/Python `Decimal` values. A failed request retry reuses the same
snapshot UUID, allowing the backend to return the original durably stored response.

The backend retrieves one coherent market snapshot, calculates all metrics, assesses risk,
optionally asks OpenAI to reason over compact structured context, and validates every proposed
action with deterministic code. Provider keys are backend environment secrets and never enter
iOS, API responses, persisted analysis payloads, or operational logs.

## Current phase

Phase 12 repository preparation is implemented. The iOS MVP guides the full daily workflow from manually entered
balances and order statuses through a clearly stateful Analyze/Retry action, a decisions-first
analysis detail screen, and useful local History rows. Inline validation, destructive-action
confirmation, keyboard dismissal, Dynamic Type-friendly layouts, explicit analysis-mode labels,
timeout/retry messaging, and compact Decimal-safe financial formatting are in place. The app also
states that it never executes trades and explains the minimized backend/OpenAI data boundary.

Staging and production configuration fail fast unless live market data, an explicitly selected
CoinGecko Demo/Pro credential mode, explicit OpenAI enablement, and PostgreSQL-backed idempotency
are configured.
OpenAI remains optional. Alembic manages the small `analysis_results` state table; completed
results survive restarts and are shared by workers. A 14-day configurable retention period and
an explicit cleanup command keep this store bounded—it is not user portfolio history.

The service provides `/health` for liveness and `/ready` for database-backed readiness, bounded
request and dependency timeouts, conservative CoinGecko GET retry, no automatic OpenAI SDK
retry, sanitized error envelopes, request IDs, and JSON operational logs. Default tests are fully
offline. A vendor-neutral single-worker process, pre-deploy migration, daily retention cleanup,
staging E2E/restart procedure, and technical privacy review are documented without selecting a
cloud vendor.

No staging or production service has been deployed because this workspace has no host account,
hostname, PostgreSQL URL, provider credentials, or deployment authorization. App Store distribution
also remains blocked by the placeholder API host and bundle ID, absent Apple signing identity and
AppIcon, unresolved device-family decision, privacy metadata/policy URL, and plan-specific
CoinGecko licensing/attribution. See [`docs/release-checklist.md`](docs/release-checklist.md) for the
authoritative blocker classification. No post-MVP feature work is part of Phase 12.
