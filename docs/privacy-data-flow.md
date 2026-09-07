# Technical privacy data flow

This document records observed Phase 12 implementation behavior for privacy and legal review. It
is not a privacy policy, legal advice, or a substitute for reviewing the deployed environment.

## Data entered and stored on iOS

The user manually enters asset symbols and quantities, conservative constraints, and manually
tracked limit-order details/statuses. SwiftData stores the editable draft, immutable portfolio
snapshots, and completed analyses on the device. The app does not request an exchange account,
wallet connection, private key, seed phrase, advertising identifier, contact list, or device
identity for the analysis flow. No advertising or tracking SDK is included.

## iOS to backend

On Analyze, iOS sends the selected immutable snapshot to the configured backend over URLSession.
The payload contains:

- snapshot UUID and timestamp
- manually entered asset symbols and quantities
- trading style, risk tolerance, leverage permission, monthly-income amount, and stable reserve
- manually entered limit-order UUID, symbol, side, USD amount, target price, state, and timestamps

The backend returns one structured `PortfolioAnalysis`. Provider keys, prompts, model metadata,
token usage, and raw candle data do not enter the iOS contract. Release requires an HTTPS,
non-loopback backend origin and has no insecure ATS exception.

## Backend processing and retention

The backend validates the request, asks CoinGecko only for market data keyed by supported asset
identifiers, calculates portfolio/technical metrics deterministically, runs risk rules, and returns
a validated analysis. CoinGecko does not receive the user's quantities, constraints, orders,
snapshot ID, or local history from this implementation.

PostgreSQL stores one idempotency row keyed by snapshot UUID. The row includes a canonical request
fingerprint, lease/state metadata, and the final validated analysis JSON so retries survive restart.
It is retained for 14 days by default and removed by an operator-scheduled cleanup command. This is
operational retry state, not the user's long-term history. Actual backups, host logs, region,
access controls, and deletion behavior must be confirmed for the selected deployment.

Structured application logs allowlist request/snapshot IDs, analysis mode, outcomes, counts,
latency, model name, and token counts. They exclude the entered portfolio, constraints, orders,
prompts, API keys, raw candles, and raw provider/model payloads. The selected host's access-log and
platform behavior require a separate production verification.

## Optional OpenAI processing

When `OPENAI_ENABLED=false`, no analysis context is sent to OpenAI. When enabled, the backend sends
one compact calculated context containing portfolio metrics, constraints, open-order summaries,
risk limits, allocations, and compact per-asset market features. It does not send raw candles,
provider payloads, snapshot/order UUIDs, request metadata, full historical analyses, exchange
credentials, wallet secrets, device identifiers, or contact/account identity. The Responses API
request sets `store=False`; the configured provider account and current OpenAI terms/data controls
must still be reviewed before release.

All proposed actions return through the deterministic RiskEngine before inclusion in the response.
The LLM does not calculate authoritative financial metrics.

## Release facts still required

Before drafting public policy language or App Store privacy answers, record:

- backend host/legal operator, processing region, access controls, log retention, backups, and
  deletion process
- selected CoinGecko plan, contract, purpose, and attribution
- whether OpenAI is enabled, the approved model/account data controls, and subprocessors
- public privacy-policy and support URLs
- whether the production app collects data linked to a user under Apple's current definitions

Only the final deployed facts should be used for legal disclosures.
