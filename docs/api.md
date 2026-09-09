# API

## Status

Phase 10 implements `GET /health`, `GET /ready`, and `POST /v1/portfolio/analyze`. The portfolio
endpoint validates an immutable snapshot, values it through the configured static or live public
market provider, calculates portfolio metrics, and applies the risk engine. OpenAI reasoning is
optional, backend-only, and disabled by default. It does not use an exchange and never executes a
trade.

## `GET /health`

Returns `200 OK`:

```json
{
  "status": "ok"
}
```

This is a lightweight liveness probe. It does not call the database, CoinGecko, or OpenAI.

## `GET /ready`

Returns `200` with `{"status":"ready","database":"ok"}` when production persistence and its
migrated table are reachable. Process-local development returns `database: "not_required"`.
Unavailable durable persistence returns `503` with
`{"status":"not_ready","database":"unavailable"}`. Readiness never probes market or model
providers.

## `POST /v1/portfolio/analyze`

### Request

All financial values cross the HTTP boundary as base-10 JSON strings. The backend parses them
into Python `Decimal`; clients must not send JSON floating-point numbers.

```json
{
  "snapshot_id": "fe603898-9a8a-4e9b-a2fc-26ba0b649964",
  "created_at": "2026-09-04T09:42:00Z",
  "portfolio": {
    "positions": [
      {"symbol": "BTC", "amount": "0.0198"},
      {"symbol": "LINK", "amount": "8.630000000000001"}
    ]
  },
  "constraints": {
    "trading_style": "active",
    "risk_tolerance": "conservative",
    "leverage_allowed": false,
    "additional_monthly_income_usd": "0",
    "minimum_stable_reserve_usd": "800.000000000000001"
  },
  "orders": [
    {
      "id": "c454346d-e263-4c8e-aac5-b63514d8c3fc",
      "symbol": "BTC",
      "side": "buy",
      "amount_usd": "200.000000000000001",
      "target_price": "76500.125",
      "status": "open",
      "created_at": "2026-09-03T09:42:00Z",
      "resolved_at": null
    }
  ]
}
```

Rules:

- `snapshot_id` and order `id` are UUIDs; timestamps are RFC 3339 date-times.
- Symbols are uppercase, 1–20 characters, and may contain letters, digits, `.`, `_`, or `-`.
- Position `amount` is zero or greater; portfolio symbols must be unique.
- Constraint amounts are zero or greater.
- Order `amount_usd` and `target_price` are greater than zero.
- `trading_style` is `active`; `risk_tolerance` is `conservative`, `moderate`, or `aggressive`.
- Order `side` is `buy` or `sell`; `status` is `open`, `filled`, or `cancelled`.
- `resolved_at` is a required nullable field. An open order sends `resolved_at: null` and cannot
  have a non-null resolution date.
- Orders are manually tracked input only. No endpoint places or changes an order.
- Request bodies are limited to 64 KiB by default. Larger bodies return `413 request_too_large`.
- A client may provide `X-Request-ID` using 1–128 letters, digits, `.`, `_`, or `-`. Invalid or
  missing values are replaced; the selected ID is returned in the response header.

### Success response

The response conforms to `contracts/portfolio-analysis.schema.json`. This sample uses fixed
development prices—BTC USD 60000 and LINK USD 15—not current market prices. Technical indicators
are absent rather than fabricated. Static remains the default so local and automated calls are
reproducible. Live mode keeps the same response shape and changes only values, timestamps, and
honest market-source language.

```json
{
  "analysis_id": "a996527a-e323-5407-91c0-f88310851f7c",
  "generated_at": "2026-09-04T09:42:00Z",
  "snapshot_id": "fe603898-9a8a-4e9b-a2fc-26ba0b649964",
  "analysis_mode": "deterministic",
  "risk_level": "high",
  "portfolio_summary": {
    "total_value_usd": "1317.450000000000015",
    "stable_value_usd": "0",
    "invested_value_usd": "1317.450000000000015",
    "stable_allocation_pct": "0",
    "open_buy_orders_usd": "200.000000000000001",
    "open_sell_orders_usd": "0",
    "deployable_stable_usd": "0",
    "allocations": [
      {
        "asset": "BTC",
        "value_usd": "1188.0000",
        "allocation_pct": "90.174200159398837638913808955950840955"
      },
      {
        "asset": "LINK",
        "value_usd": "129.450000000000015",
        "allocation_pct": "9.8257998406011623610861910440491590449"
      }
    ]
  },
  "market_summary": {
    "as_of": "2026-01-01T00:00:00Z",
    "overview": "Development market snapshot as of 2026-01-01T00:00:00+00:00. Fixed prices are available for 2 submitted assets. Technical indicators are unavailable. Values are not live. Analysis is deterministic; AI reasoning is not enabled."
  },
  "actions": [
    {
      "id": "06b9c466-32a2-53a7-b1af-2a18e90c8896",
      "asset": null,
      "type": "wait",
      "side": null,
      "price": null,
      "amount_usd": null,
      "priority": 1,
      "reason": "Wait because no stable capital is currently deployable."
    }
  ],
  "asset_analysis": [
    {
      "asset": "BTC",
      "value_usd": "1188.0000",
      "allocation_pct": "90.174200159398837638913808955950840955",
      "assessment": "Static development valuation: quantity 0.0198 at configured price USD 60000.",
      "recommendation": "The deterministic policy flags this allocation for concentration review."
    }
  ],
  "warnings": [
    {
      "code": "DEVELOPMENT_MARKET_DATA",
      "severity": "info",
      "message": "Valuations use fixed development prices, not live market data.",
      "asset": null
    },
    {
      "code": "STABLE_RESERVE_SHORTFALL",
      "severity": "critical",
      "message": "Stable capital is below the user-defined minimum stable reserve.",
      "asset": null
    }
  ]
}
```

The example abbreviates the complete `asset_analysis` and warning arrays for readability.
`analysis_mode` is `deterministic` when OpenAI is disabled, `ai_assisted` when a typed model plan
was used after deterministic validation, and `ai_fallback` when enabled reasoning failed and safe
deterministic output was returned. `generated_at` remains the snapshot creation time; market
`as_of` is the static fixture timestamp or, in live mode, the oldest quote timestamp represented
by the snapshot. Risk level is derived from deterministic policy conditions, not directly from
the tolerance label or model output.

### Portfolio calculation and risk rules

- USDT and USDC are classified as stablecoins. Static fixtures use USD 1; live mode uses actual
  provider prices.
- `invested_value_usd = total_value_usd - stable_value_usd`.
- OPEN BUY orders contribute to `open_buy_orders_usd`; FILLED and CANCELLED orders do not.
- OPEN SELL orders are reported separately and never increase stable capital before execution.
- `deployable_stable_usd = max(stable_value_usd - minimum_stable_reserve_usd - open_buy_orders_usd, 0)`.
- Additional monthly income is context, not immediately deployable capital.
- Filled orders never mutate backend portfolio balances. The submitted snapshot remains
  authoritative, and users update balances manually.

The initial development risk policy caps a new BUY at the smaller of 5% of total portfolio value
and deployable stable capital. It warns above 50% single-asset concentration, treats concentration
above 75% as extreme, warns below 15% stable allocation for non-zero portfolios, and flags open
BUY commitments at or above 20% of portfolio value. Leverage is prohibited. These are initial
product thresholds, not universal financial rules.

### Idempotency

The backend derives stable analysis/action IDs and fingerprints the complete normalized snapshot.
Production transactionally reserves a PostgreSQL row before market/OpenAI work and stores the
validated result before responding. Identical retries return the original response without
refetching market data or recalling OpenAI, including after restart or on another worker. Two
concurrent PostgreSQL workers coordinate through a unique snapshot key, row lock, and pending
lease. Reusing a snapshot UUID with different content returns `409 idempotency_conflict`.

Development may use the bounded one-process store. Durable records expire after 14 days by
default and are solely a retry mechanism, not user-visible history.

### OpenAI recommendation mode

`OPENAI_ENABLED=false` is the safe default and uses the deterministic reasoner. With OpenAI
enabled, the backend makes one Responses API call using Pydantic Structured Outputs. The input is
an explicit compact serialization of calculated portfolio metrics, constraints, manual orders,
deterministic risk assessment, and technical features. It excludes raw candles, provider bodies,
request/record IDs, conversation history, and prior full analyses.

Model output contains only a concise summary, observations, and proposed actions. It cannot set
portfolio totals, prices, timestamps, IDs, or final risk level. Each proposed action is converted
to `Decimal`-backed Domain data and independently checked for known assets, action semantics,
capital/reserve limits, policy cap, required price/amount, and leverage. Invalid proposals are
removed and produce `AI_ACTIONS_REJECTED`; if none remain, the backend emits a safe WAIT. The
model is never called a second time for rejection repair. Automatic OpenAI SDK retries are
disabled by default; one durable reservation protects each newly executed recommendation.

Timeouts, connection/API failures, rate limits, authentication errors, refusals, incomplete
responses, parse failures, and empty plans produce an `ai_fallback` response with
`AI_REASONING_UNAVAILABLE`. Invalid enabled configuration, including a missing API key, prevents
startup rather than silently changing mode.

### Market-data modes

- `static` is the safe default and uses deterministic non-live fixtures.
- `live` must be explicitly configured and uses CoinGecko public read-only endpoints.
- Live mode requires the backend-only `COINGECKO_API_KEY` and never falls back to fixtures.
- The API response intentionally does not expose provider IDs, credentials, or raw candles.
- `market_summary.overview` identifies live public data and the actual analysis mode.

### Errors

Errors use one stable envelope:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Market price is unavailable for JITO."
  }
}
```

- `400 invalid_request` — transport is valid but a portfolio, calculation, or risk invariant
  fails.
- `422 malformed_request` — Pydantic cannot parse the transport shape, type, enum, or format.
- `400 unsupported_symbol` — no exact configured provider mapping exists for a requested asset.
- `502 malformed_market_data` — provider data is missing, structurally invalid, or non-positive.
- `503 provider_unavailable` — timeout, connection failure, or unsuccessful upstream status.
- `503 provider_rate_limited` — the upstream provider returned rate-limit status.
- `503 stale_market_data` — a quote or the latest usable candle exceeds freshness policy.
- `409 idempotency_conflict` — a snapshot UUID was reused with different normalized content.
- `503 persistence_unavailable` — the durable store cannot safely reserve or return a result.
- `503 analysis_timeout` — the 45-second total analysis budget was exhausted.
- `413 request_too_large` — the request exceeds the configured body limit.
- `500 internal_error` — an unexpected server failure; stack traces are not returned.

Handled OpenAI runtime failures do not use this error envelope under the optional policy;
they return `200` with `analysis_mode=ai_fallback` and a safe warning. The API never returns the
model name, token usage, prompt, provider response ID, or credential.
