# iOS application

Step 9H makes the active Dashboard and History server-backed views of Advanced Trading Advisor
(ATA) portfolio with account, financial/core-policy, and limit-order lifecycle editing.
`GET /v1/portfolio` and complete successful mutation responses are its only confirmed-state
sources. The former CPA editor,
autosave, and Analyze flow remain in the source tree for legacy coverage but are no longer in app
navigation. The active History uses authenticated ATA recent/latest/detail reads; local CPA analyses
remain on disk for legacy coverage but are not displayed or used as a fallback. The app
does not execute trades.

## Configuration

- Project: `CryptoPortfolioAdvisor.xcodeproj`
- Scheme: `CryptoPortfolioAdvisor`
- Swift language mode: Swift 6
- Strict concurrency checking: Complete
- Deployment target: iOS 18 or later
- UI: SwiftUI
- State management: The Composable Architecture 1.26.2 or a compatible 1.x update
- Persistence: SwiftData, configured at the application composition root
- Debug backend: `CPA_BACKEND_BASE_URL=http://127.0.0.1:8000`
- Release backend:
  `CPA_BACKEND_BASE_URL=https://crypto-portfolio-advisor-api.onrender.com`
- ATA backend: set the separate, non-secret `ATA_BACKEND_BASE_URL` app-target build setting for
  each configuration before using the ATA Dashboard. Both configurations default to empty and
  show a configuration state; neither falls back to the CPA URL. The setting is copied into the
  corresponding Info.plist. Release accepts only a non-local HTTPS ATA URL. Debug may use a
  local HTTP ATA service under its existing local-network allowance. Do not put credentials in
  build settings, scheme arguments, or Info.plist.
- Temporary app bundle identifier: `com.example.CryptoPortfolioAdvisor`

`PortfolioAPIConfiguration` reads the CPA build-setting-backed Info.plist key. Release accepts only HTTPS
and rejects localhost/loopback. Debug alone has `NSAllowsLocalNetworking`; Release has no insecure
ATS exception. The Release URL targets the approved Render staging deployment. Replace the bundle
identifier only after its real value is approved, then verify the signed build against the
staging-first deployment runbook.

No separate Staging Xcode configuration is added in Phase 12. Until a real staging hostname and
signing workflow exist, another project configuration would duplicate unresolved settings. An
operator may pass the approved staging HTTPS value as a Release-compatible build-setting override
for a signed staging smoke build; the compiled non-Debug validation still enforces HTTPS and rejects
loopback hosts. Never weaken ATS for staging.

## Active ATA Dashboard

The Dashboard checks for a valid ATA URL and a Keychain bearer credential before one initial
portfolio GET. A secure credential sheet permits saving or replacing a token without displaying
the stored value; deleting it immediately hides the server portfolio. A user can explicitly
refresh or retry a read. Failed refreshes leave the last successfully loaded server portfolio
visible with a stale-data notice. Late GET responses are ignored using request generations.
Server revision and account-level holdings, aggregate holdings, financial settings, core
positions, and limit orders are displayed without local valuation. Account, policy, and order edits
are transient drafts, submitted with the current server revision; only the complete server response
confirms a change. Revision conflicts and uncertain outcomes require a fresh server read and
manual review, never an automatic replay. Open limit orders can be created, cancelled, or
expired through ATA; confirming an external fill requires the complete actual post-fill holdings
of the owning account and an explicit USDT/USDC settlement choice. None of these actions executes
an exchange trade. An uninitialized server is shown explicitly; old CPA drafts are never uploaded
or treated as confirmed state.

## Active ATA History

History loads at most 20 recent ATA run summaries in server order and separately requests the
latest completed analysis. Selecting a run loads its full detail by run UUID. A run without a
result shows status and failure metadata without invented recommendations. Historical snapshot
IDs are displayed as historical context and are never replaced by the current Dashboard
snapshot. Refresh is manual; credential changes clear prior analysis presentation. There is no
local CPA fallback, analysis cache, or Analyze Now action.

## Legacy CPA Dashboard and submission (inactive)

Dashboard editing uses feature-level `AssetPositionDraft`, `TradingConstraintsDraft`, and
`LimitOrderDraft` values. Financial fields remain raw `String` values while the user types, so
partial text can exist without weakening Domain invariants.

Analyze parses the strings into Foundation `Decimal`, delegates invariants to Domain initializers,
and creates a snapshot with injected UUID/date dependencies. The snapshot is persisted before it
is sent to the injected analysis client. The returned `PortfolioAnalysis` is mapped into Domain
and persisted before the Dashboard reports completion.

The reducer distinguishes snapshot-save, request, timeout, and analysis-save failures. The
prominent action changes between Analyze, Analyzing, and Retry. Draft controls and reducer-level
mutations are disabled while the sequence is active so the response always describes the saved
snapshot. A request retry submits the exact already-saved snapshot again—its
UUID and timestamp do not change and the snapshot is not reinserted. If only the analysis save
fails, retry saves the already-decoded result without repeating the request. Concurrent Analyze
actions are ignored.

The Dashboard uses native adaptive Form controls, inline validation, keyboard dismissal, an
empty-state explanation, and confirmation before removing assets or orders. An order changing to
Filled or Cancelled receives a resolution timestamp; changing it back to Open clears that value.
No status change mutates the portfolio—the user is explicitly reminded to update balances after a
fill. Leverage-off is labeled as spot only.

## Legacy CPA backend connection (inactive from Dashboard)

Start the service from `backend/` before running the app:

```bash
source .venv/bin/activate
python -m pip install -e '.[dev]'
uvicorn app.main:app --reload
```

An iOS Simulator can reach the host service at `http://127.0.0.1:8000`. The URL is centralized in
the app target build setting and validated by `PortfolioAPIConfiguration`. The Debug
Info.plist permits local-network HTTP for this workflow; Release does not include that exception.
A future production-host change must update the central HTTPS build setting rather than broadening
ATS.

The API implementation uses URLSession `data(for:)` with dedicated, bounded 120-second request and
resource timeouts that allow for staging cold start plus the backend's 45-second total analysis
budget, JSON content type, per-attempt request ID, status-code handling, stable
error-envelope decoding, and structured-concurrency cancellation.
Request/response DTOs own snake_case keys and decimal strings; Features see only Domain values and
the `PortfolioAnalysisClient` async capability.

Portfolio calculation, stablecoin classification, market-data access, and risk policy remain
backend responsibilities. iOS does not reproduce those rules; it decodes their structured result.

User-visible failure messages are allowlisted: market failures ask the user to retry market data,
transport failures report that the analysis service cannot be reached, and other server failures
report temporary service unavailability. Raw Python, CoinGecko, OpenAI, database, and HTTP details
are not shown. Backend `ai_fallback` remains a successful analysis with its existing label.

If the HTTP response is lost after backend completion, Retry sends the exact saved snapshot UUID
and payload. Durable backend idempotency returns the original analysis without another market or
model call. Local analysis persistence is ID-idempotent, so the same result is not stored twice.

## Legacy CPA local persistence (not ATA portfolio authority)

Draft, snapshot, and completed-analysis persistence have separate lifecycle rules:

- One mutable Dashboard draft retains raw editing strings exactly and autosaves after a
  400-millisecond TCA-clock debounce.
- Portfolio snapshots are append-only. A duplicate snapshot ID is rejected, and later draft
  changes cannot rewrite history.
- Portfolio analyses are immutable records linked by `snapshotID`. Re-saving the same result is
  idempotent; different content cannot overwrite an existing analysis ID.

Snapshot and analysis financial values are explicitly mapped to canonical POSIX decimal strings
and parsed back into `Decimal`; neither persistence nor DTOs uses `Double`. A SwiftData
`ModelActor` owns the live and in-memory-test `ModelContext`, so no context or `@Model` value leaks
into Features. The snapshot and its analysis remain independently readable through their IDs.

On restoration, a saved draft takes precedence. If it is absent, the latest snapshot seeds fresh
editable state. Loading or saving failures leave the in-memory Dashboard usable.

## Analysis history and details

History loads completed `PortfolioAnalysis` values through the persistence capability. Results
are ordered by `generatedAt` descending and UUID string ascending for timestamp ties. A saved
snapshot without a completed analysis is not shown as a successful result.

Rows show the analysis date, total value, risk level, action count, and full analysis-mode status.
Selecting a row sends the already-loaded immutable analysis into TCA-owned optional navigation.
Details are read-only and decisions-first: source and risk appear before priority-ordered actions
and severity-ordered, de-duplicated warnings; metrics, allocations, market context, and asset
observations follow. The fallback label always says deterministic analysis was used. Phase 5
snapshot persistence/details
remain available for restoration and future linked context, but the main History tab means
completed analyses.

Action priorities are a presentation-only deterministic mapping: values 1–2 display as High,
3 as Medium, and 4 or above as Low. The stored/backend priority is unchanged. Warnings sort
Critical, Warning, then Information, retain backend order within a severity, and collapse repeated
code/asset pairs for display.

Display formatting never converts financial `Decimal` values to `Double`. USD totals use normal
currency precision, quantities retain useful fractional precision, percentages have a `%` suffix,
and a tiny nonzero value is never presented as zero. Stored and transported values remain exact.

## Accessibility and user transparency

The MVP uses semantic system colors, Dynamic Type, native controls, textual labels in addition to
icons/color, VoiceOver labels for errors and status, and scrollable layouts that remain usable on
small screens. Decimal keyboards have a Done action and scrolling dismisses the keyboard.

Dashboard and Analysis Details state that the product provides analytical information, does not
execute trades, and leaves decisions with the user. Dashboard also explains that manually entered
portfolio data is sent to the backend, no exchange credentials are used, and optional AI receives
only minimized calculated context without raw candles or personal identifiers.

## Domain and boundaries

Domain contains immutable value types for portfolios, constraints, manually tracked limit
orders, snapshots, and structured analyses. `AssetSymbol` is open-ended and normalizes values such
as LINK to uppercase. Financial quantities, prices, USD values, and percentages use `Decimal`.

`AnalysisMode` is a small Domain enum. Persistence writes it losslessly and defaults Phase 6–8
payloads that lack the field to `deterministic`. iOS does not know the OpenAI model, prompt, token
usage, response ID, or API key.

Domain does not import SwiftUI, TCA, SwiftData, Combine, or networking APIs. Features depend on
Domain and small async dependency abstractions. Data implements those abstractions with SwiftData,
DTO mapping, and URLSession. No Feature handles an `@Model` or transport DTO.

There is no iOS portfolio calculator, risk engine, market provider, indicator calculator, exchange
integration, trade execution, or OpenAI SDK integration. All market and model access remains on
the backend. iOS has no CoinGecko client and stores no provider credential. Combine, RxSwift,
`OperationQueue`, and `DispatchQueue`-based business logic are excluded.

## Build and test

From `ios/`:

```bash
xcodebuild \
  -project CryptoPortfolioAdvisor.xcodeproj \
  -scheme CryptoPortfolioAdvisor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipMacroValidation \
  build

xcodebuild \
  -project CryptoPortfolioAdvisor.xcodeproj \
  -scheme CryptoPortfolioAdvisor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipMacroValidation \
  test
```

Use any installed iOS 18-or-later simulator. `-skipMacroValidation` is appropriate for a
non-interactive build only after reviewing the versions in `Package.resolved`; Xcode may instead
request package-macro approval interactively. With the currently installed Xcode 26.5 toolchain,
the generic simulator destination can fail while expanding TCA package macros; a named simulator
destination is the verified workaround. See [`../docs/release-checklist.md`](../docs/release-checklist.md)
before distribution. Physical-device, signing, VoiceOver, final universal-vs-iPhone-only support,
and install-over-install legacy-data verification remain manual release gates because they cannot
be established by an unsigned simulator build.
