# Architecture

## Product goal

CryptoPortfolioAdvisor helps a user review a manually entered cryptocurrency portfolio and
receive structured daily recommendations. The user supplies balances, conservative trading
constraints, and the state of manually placed limit orders. The product analyzes and records
that state but never executes a trade.

The Phase 11 implementation prepares and validates Dashboard input, persists immutable snapshots,
and requests portfolio valuation and risk analysis from the backend. Valuation uses an injected
static fixture or live public CoinGecko provider. Live market features are calculated server-side
from closed candles. An optional backend-only OpenAI reasoner may propose recommendations from the
compact calculated context, but deterministic backend policy remains authoritative. A small
durable backend store makes retries operationally safe while completed analyses remain available
to the user through read-only on-device History and details.

## iOS architecture

The iOS client uses the SwiftUI App lifecycle, Swift 6 strict concurrency, The Composable
Architecture (TCA), SwiftData, and dependency injection.

The intended responsibilities are:

- **Presentation/features:** SwiftUI views and TCA reducers own UI state, user actions, and
  navigation.
- **Domain:** value types and use cases describe portfolio entry, order tracking, analysis
  history, and draft creation without depending on UI, networking, or persistence details.
- **Dependencies:** small async capability values form the boundary Features call.
- **Data:** dependency implementations translate between domain or persisted values, backend
  contracts, and SwiftData records.

Feature logic is unit-testable through injected persistence and analysis-client dependencies.
Asynchronous work uses
Swift Structured Concurrency and `async`/`await`. Combine, RxSwift, and `DispatchQueue`-based
business logic are excluded.

### Domain model

The Phase 2 domain model is framework-independent Swift. It imports Foundation only where
fundamental value types such as `UUID`, `Date`, and `Decimal` are required; it does not import
SwiftUI, TCA, SwiftData, Combine, or networking APIs.

Asset identifiers use an open `AssetSymbol` value type rather than a closed enum. Symbols are
normalized to uppercase, and arbitrary non-empty assets such as `LINK` remain valid. All asset
quantities, USD amounts, prices, and allocation percentages use `Decimal`, never `Double`, to
avoid binary floating-point representation in financial values.

`PortfolioSnapshot` is the immutable user-supplied state for one daily analysis: portfolio,
constraints, and manually tracked orders. `PortfolioAnalysis` is the separate generated result
and references the exact snapshot by ID. Keeping these concepts separate prevents later edits
to a draft portfolio from changing historical analysis inputs.

### Dashboard draft boundary

The Phase 3 Dashboard owns feature-level draft models rather than placing partially typed values
in Domain models. Asset amounts, order amounts and prices, monthly income, and stable reserve are
kept as raw strings while editing. On Analyze, a small feature-local parser accepts a period or
comma/current-locale decimal separator, rejects other non-numeric characters, and normalizes the
value before creating a Foundation `Decimal`. Grouping semantics are intentionally unsupported;
separator characters represent only a decimal point.

Conversion then delegates business invariants to the strict Domain initializers and returns a
small `ValidatedDashboardInput` containing `Portfolio`, `TradingConstraints`, and `[LimitOrder]`.
Feature-level parsing and user-facing field errors do not weaken or replace Domain validation.
The validated aggregate remains in TCA state. Analyze creates an immutable `PortfolioSnapshot`
with injected UUID and date values, persists it, submits that exact value to the injected
`PortfolioAnalysisClient`, and persists the returned `PortfolioAnalysis` separately.

Submission has explicit idle, submitting, success, and boundary-specific failure states. A
snapshot failure stops before networking. A request failure retains the already-saved snapshot,
and retry reuses its UUID and date without saving another snapshot. An analysis-persistence
failure retains the decoded result and retries only the final local save. Concurrent Analyze
actions are ignored while submission is active.

### SwiftData persistence boundary

Features call a minimal async `PortfolioPersistenceClient` value. Its live implementation is
composed at the app root and delegates to a SwiftData `ModelActor`; tests provide controlled
closures or a `ModelContainer` configured only in memory. The actor owns its `ModelContext`, and
neither contexts nor `@Model` instances leave Data/Persistence. This follows SwiftData-supported
actor isolation under Swift 6 complete concurrency checking without custom `@unchecked Sendable`.

The current draft, historical snapshots, and analyses have different lifecycle rules:

- One mutable draft record stores plain persisted asset, constraint, and order representations.
  Raw financial strings are retained exactly so partially typed editing state survives relaunch.
- Snapshot records are append-only. Their UUID and creation date remain queryable, while their
  positions, constraints, and orders are explicitly encoded as a separate immutable payload.
  A duplicate snapshot UUID is rejected rather than updating history.
- Analysis records are immutable and ID-based. The complete result is encoded with financial
  `Decimal` values as canonical strings. Re-saving the identical result is a no-op;
  attempting to overwrite its ID with different content fails.

On first Dashboard task execution, the reducer restores the current draft. If no draft exists,
it loads the latest snapshot and copies its portfolio, constraints, and all order statuses into a
new editable draft. If neither exists, or a load fails, product defaults remain usable. Snapshot
copies receive fresh feature-only position row IDs; Domain order IDs and their lifecycle values
are retained.

Each edit mutates TCA state immediately and schedules a save after 400 milliseconds. The effect
uses the injected continuous clock, TCA cancellation, and structured concurrency; a newer edit
cancels the earlier pending save. A failure only changes a small status value and never discards
the in-memory draft.

Snapshot and analysis financial `Decimal` values are mapped to canonical `en_US_POSIX` strings
and parsed back explicitly. No financial value is persisted through `Double`, providing
predictable lossless round trips. Analyses reference snapshots through `snapshotID`; no SwiftData
object relationship is required, and either historical record remains independently readable.
The stored analysis payload includes `analysisMode`; legacy Phase 6–8 payloads that lack it decode
as `deterministic` without changing the SwiftData entity schema.

### Analysis history boundary

History and Dashboard are sibling TCA features and do not send actions or state to each other.
Both depend on `PortfolioPersistenceClient`, making SwiftData the communication boundary and
source of truth. History reloads completed analyses whenever it appears and represents idle,
loading, loaded, empty, and failed UI states locally; failed loads expose a focused retry action.
Snapshot-only records are intentionally excluded because they are not successful analyses.

The persistence client returns analyses ordered by `generatedAt` descending. UUID string
ascending is the deterministic secondary order for equal timestamps. The MVP loads the complete
local set; pagination is intentionally deferred. Snapshot query capability remains available for
draft restoration and future linked context.

History uses `PortfolioAnalysis.id` for row identity. Each row exposes its local date, total value,
risk, action count, and complete analysis-mode label. Selecting a row places its complete,
already-loaded immutable analysis into optional TCA presentation state and pushes a read-only
`AnalysisDetailsFeature`. Details are decisions-first: analysis source and risk precede
priority-ordered actions and severity-ordered, de-duplicated warnings; portfolio metrics,
allocations, market context, and asset observations follow. The detail reducer has no mutation
actions, and SwiftData entities never cross into either feature.

Snapshot dates are formatted at display time with locale-aware Foundation APIs. Financial values
remain `Decimal` and are formatted through `NSDecimalNumber` and a locally configured
`NumberFormatter`; no `Double` bridge or stored display string is introduced. Presentation applies
compact currency, quantity, and percentage precision while preserving enough fractional digits to
ensure a nonzero value never appears as zero. Exact persisted and transported values are unchanged.
The earlier read-only snapshot details remain available in the codebase, but the main History tab
now means completed analysis history.

### MVP presentation boundary

Phase 11 keeps polish in Views and small pure presentation helpers rather than adding Domain or
Data responsibilities. Dashboard fields remain editable draft state, but both the controls and
reducer mutation paths reject changes while an analysis submission is active. This makes the
saved immutable snapshot the unambiguous request input. Destructive row removal is confirmed,
validation stays adjacent to fields, native scroll/keyboard behavior supports small screens, and
order-status changes record resolution time without changing portfolio balances.

Analysis mode, action priority, warning severity, and risk always have textual labels; icons and
semantic colors are supplementary. Views use native SwiftUI controls and Dynamic Type rather than
fixed-height layouts. Dashboard and details disclose that the product does not trade and that
decisions remain the user's. Dashboard also describes the network boundary: manually entered data
goes to the backend, exchange credentials are not used, and optional AI sees only minimized
calculated context without raw candles or personal identifiers.

### HTTP transport boundary

Features depend on a small async `PortfolioAnalysisClient` capability, never on URLSession or
DTOs. The Data/API implementation explicitly maps `PortfolioSnapshot` to a snake_case request DTO,
uses URLSession's async `data(for:)`, validates HTTP status, decodes the stable backend error
envelope, maps a response DTO into Domain, and propagates cancellation. The backend URL comes from
the single `CPA_BACKEND_BASE_URL` build setting. Debug defaults to `http://127.0.0.1:8000` and
alone permits local-network HTTP. Release requires HTTPS, rejects loopback hosts, and has no local
ATS exception. Backend and transport failures map to concise messages rather than provider or
HTTP implementation details.

Financial transport values are strings on both DTOs and Python's HTTP models. Explicit POSIX
decimal conversion preserves precision and prevents JSON binary floating point from entering the
contract.

## Backend architecture

The backend is a FastAPI application with Pydantic at its HTTP boundary and asynchronous I/O.
The components and their current boundaries are:

- `MarketDataProvider`: async retrieval of compact `MarketSnapshot` values. Phase 8 retains the
  deterministic `StaticMarketDataProvider` and adds one live CoinGecko implementation.
- `TechnicalFeatureCalculator`: deterministic Decimal features from normalized, closed 4-hour
  candles. Raw candle arrays do not cross this boundary.
- `AnalysisContextBuilder`: compact internal portfolio, constraint, order, risk, market-feature,
  and allocation context.
- `AnalysisContextSerializer`: an explicit, reviewed data-minimization map for model input. It
  emits canonical decimal strings and excludes candles, provider bodies, IDs, metadata, and
  history.
- `PortfolioCalculator`: deterministic portfolio values, allocations, open-order commitments,
  stable capital, and deployable capital.
- `RecommendationReasoner`: application-facing async protocol implemented by the deterministic
  reasoner and the OpenAI infrastructure adapter.
- `OpenAIRecommendationService`: one official async Responses API call with Pydantic Structured
  Outputs, no tools, and no conversation state.
- `RiskEngine`: centralized policy assessment and independent validation of every proposed action.
- `AnalysisService`: orchestration of request validation, market retrieval, calculation, risk
  evaluation, optional recommendation reasoning, action filtering, and response construction.
- `AnalysisIdempotencyStore`: application-facing result reuse and coordination. Development uses
  a bounded in-process implementation; production uses SQLAlchemy async with PostgreSQL.
- `BudgetedAnalysisService`: an outer deadline around analysis and duplicate waiting.

API routes translate Pydantic HTTP models into backend Domain values. Services orchestrate domain
behavior. Infrastructure owns HTTP clients, provider-specific decoding, and database access.
Phase 10 centralizes environment validation and wires the provider, calculators, optional
reasoner, total budget, and idempotency decorator once in `app.dependencies`; route handlers do
not instantiate them. Despite its retained compatibility
name, `DeterministicPortfolioAnalysisService` now means the deterministic analysis orchestrator:
all public metrics, risk, identifiers, timestamps, and final action acceptance remain code-owned.

The production store claims work with a PostgreSQL row lock, unique snapshot key, owner token, and
short lease. Normal duplicates during that lease share one execution. A worker that is suspended
past the lease can overlap a takeover when it resumes, but its stale owner token cannot replace the
winner's record; the configured lease exceeds the inner analysis deadline to keep this pathological
case outside normal operation.

The backend uses Python `Decimal` for financial input and service values. Business validation is
separate from Pydantic shape validation. Percentage calculations use a 38-digit local Decimal
context and explicitly return zero for zero-value portfolios. The route contains mapping only.

### Compact market context

`MarketSnapshot` contains an `as_of` timestamp and one compact `MarketAssetSnapshot` per requested
asset. Each asset can carry price, 24-hour and 7-day change, RSI, EMA20, EMA50, ATR, support, and
resistance as Decimal values. Raw candles are excluded.

CoinGecko was selected because its documented read-only API supports batched USD prices with
`last_updated_at`, explicit asset IDs, and OHLC history for BTC, ETH, SOL, LINK, USDT, and USDC.
The implementation uses the documented
[`/simple/price`](https://docs.coingecko.com/reference/simple-price) and
[`/coins/{id}/ohlc`](https://docs.coingecko.com/reference/coins-id-ohlc) endpoints. A 30-day OHLC
request has automatic 4-hour granularity, and CoinGecko defines the timestamp as the candle close
time. The [current Demo plan](https://www.coingecko.com/en/api/pricing) documents 100
requests/minute, 10,000 monthly calls, data freshness from 60 seconds, and attribution
requirements. Production deployment must confirm the applicable CoinGecko plan, license,
attribution, and service-level requirements.

Phase 12 makes credential routing explicit: Demo uses `api.coingecko.com` with the
`x-cg-demo-api-key` header, while Pro uses `pro-api.coingecko.com` with
`x-cg-pro-api-key`. Staging and production must select the tier explicitly; the repository does
not select a commercial plan or infer account terms.

Symbol mapping is centralized and exact: BTC→bitcoin, ETH→ethereum, SOL→solana,
LINK→chainlink, USDT→tether, and USDC→usd-coin. Unmapped symbols fail as
`unsupported_symbol`; another coin is never substituted. One batch request fetches current USD
prices and one OHLC request per unique symbol provides all indicator input. Live USDT/USDC use
provider prices rather than forced parity. Static fixtures retain the explicit USD 1 development
assumption.

### Closed candles and technical definitions

Only candles whose provider close timestamp is at or before the analysis clock are used. A future
close represents an incomplete candle and is excluded. Thirty days yields roughly 180 4-hour
candles, sufficient to warm EMA50 without requesting excessive history.

- 24-hour change compares the latest close with the close six 4-hour intervals earlier.
- 7-day change compares the latest close with the close 42 intervals earlier.
- RSI14 uses Wilder average gains and losses over closed candles; all-flat history returns 50.
- EMA20 and EMA50 use the simple average of their first period as the seed, then the standard
  Decimal EMA recurrence.
- ATR14 uses standard true range and Wilder smoothing.
- Support is the lowest low, and resistance the highest high, over the latest 20 closed candles.

If history is valid but insufficient, only the affected optional features are `None`; current
price valuation may continue. Values are never fabricated.

### Market configuration, freshness, and failures

`MARKET_DATA_MODE=static` is the safe default used by tests. Live mode must be selected explicitly
and requires `COINGECKO_API_KEY` in the backend environment. Request timeout, maximum quote age,
and maximum closed-candle lag are centralized and configurable. Defaults are 10 seconds, 10
minutes, and 5 hours respectively. Live mode never silently falls back to fixtures.

HTTP cancellation propagates naturally. Provider timeouts/connection/status failures,
rate-limits, unsupported symbols, stale values, and malformed or non-positive data have separate
safe error codes. Raw provider responses and credentials never enter logs or API errors. Default
tests inject HTTPX mock transports and perform no internet access. There is no market-data cache or
unbounded retry framework. CoinGecko GETs receive at most one retry for transport or `5xx`
failures and are not retried on rate limiting. Completed-result reuse remains a separate boundary.

### Portfolio metrics and open orders

`PortfolioCalculator` owns all valuation math. For each position it multiplies quantity by the
matching market price, then calculates total value, stable value, invested value, allocation
percentages, stable allocation, largest allocation, open BUY commitments, open SELL commitments,
and deployable stable capital. A missing or non-positive market price fails explicitly.

Deployable capital is:

```text
max(stable_value_usd - minimum_stable_reserve_usd - open_buy_orders_usd, 0)
```

Only OPEN BUY orders reduce deployable capital. FILLED and CANCELLED orders do not. OPEN SELL
orders are tracked separately and never increase stable capital before execution. Additional
monthly income is context only and is not treated as current liquidity. The submitted portfolio
is authoritative: marking an order FILLED never mutates balances; the user must update Dashboard
positions to reflect the fill, preventing double-counting.

### Initial risk policy

`RiskPolicyConfig` continues to centralize the initial development policy:

- New BUY limit: the smaller of 5% of current portfolio value and deployable stable capital.
- Concentration warning: any individual asset above 50%.
- Extreme concentration/high-risk threshold: above 75%.
- Low stable allocation warning: below 15% for a non-zero portfolio.
- Significant open BUY commitment warning: at least 20% of portfolio value.
- Leverage: prohibited by the development policy.

These values are initial product policy, not universal financial rules. The assessment is HIGH for
leverage-policy violations, reserve shortfall, or extreme concentration; MODERATE for other
concentration, low stable allocation, or significant commitments; and LOW otherwise. Empty/zero
portfolios produce zero percentages, zero new-BUY capacity, and a valid assessment.

`RiskEngine.validate_action` is the hard recommendation boundary. It rejects unknown or missing
required assets, inconsistent action/side semantics, non-positive or missing required amounts and
prices, BUY amounts above deployable capital or the 5% cap, reserve violations, SELL amounts above
current asset value, invalid priority, and leverage-dependent actions. Model actions are validated
independently: safe actions survive, rejected actions produce a warning, and an all-rejected plan
becomes a backend-generated WAIT without a second model call.

## Data flow

The Phase 11 daily flow is:

1. The user edits a local draft containing balances, constraints, and limit-order statuses.
2. iOS autosaves the raw editable draft locally.
3. Analyze validates the draft and saves an immutable local snapshot.
4. iOS maps that exact snapshot to lossless transport DTOs and posts it to the backend.
5. Pydantic validates transport shape and converts financial strings to `Decimal`.
6. The configured `MarketDataProvider` retrieves a static fixture or validated live prices and
   closed 4-hour history.
7. `TechnicalFeatureCalculator` reduces candle history to compact features; raw candles stop.
8. `PortfolioCalculator` calculates values and open-order metrics; `RiskEngine` assesses policy.
9. `AnalysisContextBuilder` combines deterministic state and compact market features from that
   same single market snapshot.
10. With OpenAI disabled, the deterministic reasoner proposes a safe rule-based plan. With it
    enabled, `AnalysisContextSerializer` sends only reviewed compact data in one stateless async
    Responses API request and parses a Pydantic Structured Output.
11. Each proposed action is converted to Domain `Decimal` values and independently passes through
    `RiskEngine.validate_action`; unsafe proposals never reach the public response.
12. A handled OpenAI failure switches to deterministic output and `ai_fallback`.
13. Before expensive work, production reserves the snapshot fingerprint. The final validated
    response is stored losslessly before return; a matching retry reads it directly.
14. iOS validates, maps, and idempotently persists the response, then exposes read-only History.
15. On the next day, the current saved draft—or the latest snapshot if the draft is absent—starts
    a new editable state. A new Analyze creates new immutable snapshot and analysis records; prior
    records cannot be rewritten.

## Persistence strategy

SwiftData is the on-device source of truth for the current Dashboard draft, committed portfolio
snapshots, and completed analyses. A snapshot is an immutable input, not a live view of
mutable Dashboard state. The latest snapshot may seed a new draft when no current draft exists;
changes to the copy cannot rewrite history. A completed analysis is separately immutable and
links back by snapshot UUID. History queries the complete analysis set because expected local MVP
scale is small; pagination can be added only when a later requirement justifies it.

Backend persistence has one narrow purpose: durable request idempotency. SQLAlchemy async stores
an `analysis_results` row keyed by `snapshot_id`, with a canonical SHA-256 snapshot fingerprint,
`pending`/`completed`/`failed` state, lease owner, timestamps, expiry, analysis ID, and final
validated analysis JSON. Every financial value in that JSON is an exact decimal string. Alembic
owns the schema. No prompt, raw provider/model response, secret, or user history is stored.

Staging and production require PostgreSQL. Its unique primary key and transactional row lock let workers
share completed responses and coordinate one active expensive operation. A matching result is
returned after restart without repeating market/model work; different content under the same UUID
returns a conflict. A crashed lease can be reclaimed after expiry. SQLite supports offline tests,
but is not a claimed production multi-worker store. Development may use the existing process cache.

Records expire after 14 days by default and cleanup is an explicit maintenance command rather
than an in-process scheduler. Backend records support retries only; SwiftData remains the
authoritative user-facing history.

## LLM boundary

The LLM is an optional constrained reasoning component, not a calculator or source of record. The
backend uses the official async Python SDK's Responses API and Pydantic Structured Outputs. The
development default is configurable `gpt-5.6-terra` at low reasoning effort: current OpenAI model
documentation identifies it as the balanced tier and confirms Responses API, reasoning, and
Structured Outputs support. `OPENAI_ENABLED=false` remains the default and does not construct a
client or make a model call.

The LLM does not calculate portfolio totals, position values, allocation percentages, order
commitments, risk limits, prices, indicators, timestamps, or identifiers. Its exact typed output is
`AIRecommendationPlan(summary, actions, observations)`, where each `AIProposedAction` contains
only asset, action type, side, canonical decimal-string amount/price, priority, and a concise
reason. No chain-of-thought is requested or stored. It cannot receive exchange credentials,
execute trades, or be called directly from iOS. The OpenAI API key remains in the backend
environment and is absent from prompts, logs, API responses, and iOS.

`AnalysisContextSerializer` reviews every transmitted field. It sends calculated metrics,
constraints, manual order values/status, deterministic risk results, and compact per-asset market
features as a separate structured user-data message. It omits raw candles, provider payloads,
snapshot/order IDs, timestamps not needed for reasoning, user/device identity, conversation
history, prior responses, and full historical analyses. Arbitrary data is never interpolated into
privileged instructions. One newly reserved analysis makes one model call, with no tools, agent
loop, per-asset calls, or automatic second attempt. SDK automatic retries default to zero. SDK
token usage is logged internally with model,
latency, outcome category, and action counts; prompts, full responses, and credentials are not.

Runtime failures, rate limits, authentication errors, refusal, incomplete or invalid structured
output, timeout, and empty plans are handled by deterministic fallback. The public result is
explicitly `ai_fallback` with a warning, never mislabeled as AI-assisted. Missing enabled
credentials are an invalid process configuration and fail startup clearly.

The model ID and reasoning effort are deployment configuration rather than Domain policy. A model
change requires Structured Output compatibility verification, the deterministic eight-case
evaluation suite, and token/latency comparison. Pricing is not hardcoded because it can change.

## Operational boundary

`AppSettings` is the only environment-policy boundary. Staging and production require live market
data, an explicit CoinGecko Demo/Pro credential mode, backend-only CoinGecko credentials, an
explicit OpenAI enable/disable decision, durable database mode, and a PostgreSQL psycopg URL.
OpenAI stays optional. Invalid settings prevent process
composition rather than silently selecting fixtures. FastAPI debug tracebacks remain disabled;
docs exposure and the 64 KiB request-size limit are explicit settings, and CORS is not opened.

Each request receives a validated or generated correlation ID and returns it in `X-Request-ID`.
Allowlisted JSON logs contain operational identifiers, latency, analysis/provider outcomes,
action counts, model/token use when available, and idempotency outcome. They omit credentials,
prompts, full portfolios, provider/model bodies, and exception text.

`/health` is process liveness and makes no dependency call. `/ready` verifies the idempotency
database/table when configured, but never calls CoinGecko or OpenAI. A failed database reservation
returns before expensive provider/model work begins. Default budgets are 10 seconds per CoinGecko
GET, 30 seconds for OpenAI, and 45 seconds for the complete analysis. The outer deadline prevents
nested work from extending the request indefinitely.

## Risk validation boundary

Risk controls are enforced by deterministic backend code. Request validation establishes valid
types and ranges; `PortfolioCalculator` establishes authoritative metrics; `RiskEngine` applies
the centralized assessment and validates each untrusted model proposal after Pydantic parsing and
Domain conversion. The final `risk_level`, capital values, market values, and public response are
never chosen by the model. Invalid actions are removed rather than repaired by an LLM; valid
siblings continue, rejection is visible as a safe warning, and all-rejected output becomes WAIT.

The iOS client may provide immediate form feedback, but backend validation remains
authoritative.

## Dependency direction

Dependencies point inward:

```text
iOS views/features -> async dependency abstractions
           |                 /                 \
           v                v                   v
       iOS domain      SwiftData mapper     API DTO/URLSession mapper

HTTP API -> application services -> domain rules
                ^                 ^
                |                 |
idempotency protocol       infrastructure adapters
                          (market data, OpenAI SDK, SQLAlchemy)
```

Domain code does not import FastAPI, persistence frameworks, networking libraries, market
providers, or OpenAI clients. Application services depend on abstractions for external
capabilities; infrastructure implements those abstractions. Transport and persistence models
are mapped at their boundaries rather than leaking through the domain.
