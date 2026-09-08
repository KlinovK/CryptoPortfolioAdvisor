# Deployment readiness

Phase 12 prepares one portable FastAPI service for staging and production. No cloud account or
hostname is selected in this repository, and no external environment has been deployed from this
workspace.

## Runtime profiles

`APP_ENV=staging` and `APP_ENV=production` are deployment profiles. Both fail at process startup
unless all of these conditions hold:

- `MARKET_DATA_MODE=live`
- `COINGECKO_API_TIER=demo|pro` is explicitly selected
- `COINGECKO_API_KEY` is present
- `OPENAI_ENABLED=true|false` is explicitly selected
- `OPENAI_API_KEY` is present when OpenAI is enabled
- `ANALYSIS_IDEMPOTENCY_MODE=database`
- `DATABASE_URL` uses the async-compatible `postgresql+psycopg://` dialect

Static market fixtures and SQLite are development/test tools and cannot start in either deployment
profile. API documentation is off by default in both profiles and may be enabled deliberately with
`API_DOCS_ENABLED=true`. Configuration validation does not contact PostgreSQL, CoinGecko, or
OpenAI; `/ready` is the post-start database check.

The backend does not load `.env` files itself. Inject settings through the hosting platform's
secret/environment facility. Never commit a populated environment file or expose secrets in logs,
iOS settings, request payloads, process arguments, or deployment output.

## Portable process model

Use Python 3.13 and install the backend package. The conservative MVP process is one ASGI worker:

```bash
python -m pip install .
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --workers 1
```

Run `alembic upgrade head` as a release/pre-deploy command and abort rollout if it fails. Running it
again on an already-current database is safe. Do not place migration execution in every app worker.
Terminate TLS at the hosting platform or reverse proxy and expose only an HTTPS public hostname.
The native iOS app does not need browser CORS.

One worker is the supported initial deployment. The PostgreSQL store is designed for cross-process
coordination, but multiple workers remain a release configuration decision until the selected host
passes the lease, termination, conflict, and restart tests in the deployment runbook.

## Database, migrations, and readiness

`DATABASE_URL` must name a dedicated PostgreSQL database using psycopg's SQLAlchemy dialect. The
initial Alembic migration creates only `analysis_results`, which stores coordination state, a
canonical snapshot fingerprint, safe identifiers, and the final validated analysis JSON. It is not
portfolio history and contains no prompt, raw provider/model response, or credential.

- `GET /health` is liveness only and never probes PostgreSQL, CoinGecko, or OpenAI.
- `GET /ready` checks the configured idempotency store/table only. Database unavailability returns
  `503`; external providers are intentionally not readiness dependencies.

The unique snapshot row and lease make a completed response durable across retry, restart, and
workers. Reusing a snapshot UUID with different input returns `409 idempotency_conflict`. The
default retention is 14 days. Schedule this idempotent command daily using the host's normal job
facility:

```bash
python -m app.tools.cleanup_analysis_records
```

Do not add an in-process scheduler or task queue for this maintenance operation.

## CoinGecko configuration review

The adapter uses two documented read-only endpoints:

- `GET /simple/price` batches current USD prices and includes `last_updated_at`.
- `GET /coins/{id}/ohlc?vs_currency=usd&days=30` returns automatic four-hour candles for the
  3–30 day window. CoinGecko documents each timestamp as the candle close time.

The supported mapping is BTC, ETH, SOL, LINK, USDT, and USDC. A six-asset analysis makes one price
request followed by one OHLC request per asset. The backend accepts only fresh quotes and closed,
continuous four-hour candles, then calculates compact technical features locally.

Authentication is plan-specific and selected by `COINGECKO_API_TIER`:

| Tier | Base URL | Header |
| --- | --- | --- |
| `demo` | `https://api.coingecko.com/api/v3` | `x-cg-demo-api-key` |
| `pro` | `https://pro-api.coingecko.com/api/v3` | `x-cg-pro-api-key` |

Official references reviewed on 2026-09-07:

- [API key setup](https://docs.coingecko.com/docs/setting-up-your-api-key)
- [Simple Price](https://docs.coingecko.com/reference/simple-price)
- [Coin OHLC by ID](https://docs.coingecko.com/reference/coins-id-ohlc)
- [Plans and current quotas](https://www.coingecko.com/en/api/pricing)
- [Commercial/custom license summary](https://support.coingecko.com/hc/en-us/articles/16760512207257-What-Are-the-Differences-Between-Commercial-and-Custom-Licenses)
- [Official attribution guide](https://brand.coingecko.com/resources/attribution-guide)

The current pricing page identifies Demo as attribution-required and currently lists 10,000 monthly
call credits and 100 requests/minute. It lists a standard commercial license for paid plans and the
official license summary requires the linked wording “Data provided by CoinGecko” for standard
commercial use. These published facts do not select a legally suitable plan for this product.

Release remains blocked until the operator selects the actual plan, verifies endpoint entitlement,
quota, commercial use, redistribution, attribution, and account-specific terms, and obtains any
needed legal approval. No attribution is hard-coded into iOS while that decision is unresolved.

## OpenAI configuration

OpenAI is optional and backend-only. When enabled, configure:

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `OPENAI_REASONING_EFFORT`
- `OPENAI_TIMEOUT_SECONDS`
- `OPENAI_MAX_RETRIES`

The implementation preserves one Responses API Structured Output call, `store=False`, no tools or
conversation state, controlled SDK retry, sanitized failure mapping, and deterministic RiskEngine
validation of every final action. A model change must pass the offline fixture suite and one
explicitly authorized live compatibility test before rollout. Do not put model configuration or an
OpenAI key in iOS.

## Timeouts, logs, and failures

CoinGecko defaults to a 10-second request timeout and one retry only for transport or `5xx`
failures; `429` is not retried. OpenAI defaults to 30 seconds and zero SDK retries. The full backend
analysis budget is 45 seconds and the iOS request timeout is 120 seconds so the staging client can
tolerate a Render Free cold start before that backend budget begins.

Single-line JSON logs contain request/snapshot identifiers, latency, analysis mode, idempotency
outcome, provider outcome, accepted/rejected action counts, and OpenAI model/token usage when
available. The allowlist excludes secrets, holdings, prompts, raw candles, and raw provider/model
payloads. Connect standard output to the selected host's normal log collection and verify the
allowlist there before production traffic.

## iOS release boundary

Debug uses `http://127.0.0.1:8000` and has the only local-network ATS allowance. Release reads the
central `CPA_BACKEND_BASE_URL`, requires HTTPS, rejects loopback hosts, and has no ATS relaxation.
Release currently targets the approved staging hostname at
`https://crypto-portfolio-advisor-api.onrender.com`. Any future host change must preserve the same
transport checks and must not introduce an ATS exception.

The bundle identifier, Apple team, signing assets, AppIcon, privacy-policy URL, App Store metadata,
device-family decision, and production API-host decision are account/product inputs, not values
this repository can invent. Follow [`deployment-runbook.md`](deployment-runbook.md) once those
inputs exist.
