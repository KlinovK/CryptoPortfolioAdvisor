# MVP release checklist

This checklist separates repository readiness from distribution-specific values that must not be
invented in source. Complete it against the selected backend host, Apple Developer account, App
Store Connect record, and CoinGecko plan before shipping.

## Product workflow

- [x] First launch explains how to add manually held balances.
- [x] Portfolio, constraints, and manually tracked limit orders can be edited and validated.
- [x] Filled/cancelled orders are timestamped but never alter balances automatically.
- [x] Analyze saves one immutable snapshot before the request and one immutable analysis after it.
- [x] Submission prevents draft mutation and duplicate Analyze actions.
- [x] Retry reuses the saved snapshot and avoids duplicate local records.
- [x] `ai_fallback` is a successful result and is clearly labeled as deterministic fallback.
- [x] History has useful rows, empty state, failed state, retry, and read-only details.
- [x] The next day's draft can start from saved state without rewriting earlier records.

## User trust and privacy

- [x] Dashboard and Analysis Details say that the app provides analysis and never executes trades.
- [x] The user is told that crypto is volatile and decisions remain their responsibility.
- [x] Dashboard explains that manually entered portfolio data is sent to the backend.
- [x] Dashboard states that exchange credentials are not used.
- [x] Dashboard explains the minimized calculated context sent to OpenAI when AI is enabled.
- [ ] Confirm App Store privacy answers against actual production backend logging, retention, and
  provider configuration.
- [ ] Add or confirm a public privacy policy URL in App Store Connect.
- [x] Review Apple's current privacy-manifest requirements for all shipped dependencies. The
  Phase 12 unsigned Release bundle contains TCA and swift-sharing manifests with declared
  UserDefaults/file-timestamp reasons, no collection, and no tracking. Recheck the final signed
  archive and generate Xcode's privacy report before upload.
- [ ] Confirm required CoinGecko attribution for the selected plan and add the approved wording in
  an appropriate product location; no plan-specific wording is currently hard-coded.

## Accessibility and device checks

- [x] Native SwiftUI controls, semantic colors, and textual status labels are used.
- [x] Error, risk, warning, mode, and completion states do not rely on color alone.
- [x] Decimal keyboards provide a Done action and scrolling dismisses the keyboard.
- [x] Destructive row removal requires confirmation.
- [ ] Manually verify VoiceOver order and labels on Dashboard, History, and Analysis Details.
- [x] Verify light and dark appearances on a small supported iPhone simulator.
- [x] Verify an accessibility Dynamic Type size uses wrapping and the native scrolling form.
- [ ] Manually verify hardware-keyboard and software-keyboard entry for every financial field.

## Release configuration

- [x] Swift 6 mode and Complete strict concurrency are enabled.
- [x] Deployment target is iOS 18.0 or later.
- [x] Release accepts only HTTPS backend URLs and rejects loopback hosts.
- [x] Release Info.plist has no local-network ATS exception.
- [x] Configure Release with the approved Render staging endpoint:
  `https://crypto-portfolio-advisor-api.onrender.com`.
- [ ] Replace temporary bundle identifier `com.example.CryptoPortfolioAdvisor`.
- [ ] Select the Apple Developer team, signing certificate, and provisioning profile.
- [ ] Add final AppIcon assets; no production icon asset is present yet.
- [ ] Confirm marketing version `1.0` and build number `1` for the intended submission.
- [ ] Confirm the intended iPhone/iPad device family and supported orientations. The current target
  supports both device families and does not declare explicit orientation keys.
- [ ] Create and validate the App Store Connect record, screenshots, description, support URL,
  privacy policy URL, age rating, category, and availability.
- [ ] Complete a signed archive validation and smoke test on a supported physical iPhone.

## Backend and operations

- [ ] Provision the production HTTPS API and PostgreSQL database.
- [ ] Select and confirm the production CoinGecko plan, key, licensing, quotas, and attribution.
- [ ] If AI is enabled, select the OpenAI model, inject its key, and run the documented offline and
  explicitly opted-in live compatibility checks.
- [ ] Run `alembic upgrade head` before application rollout.
- [ ] Inject secrets and settings described in `docs/deployment.md`; never place them in iOS.
- [ ] Verify `/health` and `/ready` from the production environment.
- [ ] Verify production rejects static market data and process-local idempotency.
- [ ] Schedule the explicit idempotency-retention cleanup command.
- [ ] Connect redacted logs to the selected monitoring/alerting system and verify timeout,
  provider, database, fallback, and readiness signals.

## Final product acceptance

- [x] Disclaimer and no-automatic-trading copy are visible in the daily workflow.
- [x] AI fallback is visibly labeled and stored as a completed analysis.
- [ ] Run the full daily workflow against the production-like backend configuration.
- [ ] Re-test legacy persisted analysis migration on an upgraded device/install before release.
- [ ] Confirm that every product and App Store statement accurately describes the deployed data
  handling and market/AI configuration.

## Phase 11 verification record

On 2026-09-06, the Debug app was built, installed, and launched on an iPhone SE (3rd generation)
simulator running iOS 26.5. The first-launch Dashboard was visually inspected in light appearance
at the standard content size and in dark appearance at the Accessibility Large content size. The
introductory content wrapped without horizontal clipping and the remaining form stayed inside its
native scroll container. Dashboard keyboard, History, and Analysis Details behavior are covered at
build/reducer/presentation level; a full manual VoiceOver, keyboard-entry, physical-device, and
production-backend smoke pass remains a release task.
- [ ] Validate request IDs, redacted JSON logs, timeout behavior, and alerting on the chosen host.
- [ ] Run the explicitly opted-in live CoinGecko and OpenAI checks with approved credentials.

## CoinGecko attribution

- [ ] Confirm the current license and attribution obligation for the exact production plan.
- [ ] If visible attribution is required, add the smallest compliant acknowledgement in a
  discoverable in-app location and record it here.
- [ ] Obtain approved attribution wording from the applicable CoinGecko terms or account agreement.

No plan-specific wording is included in the app because the production plan has not been selected
or verified. `docs/deployment.md` remains the implementation hook for this decision.

## Verification gates

- [x] iOS Debug simulator build passes.
- [x] iOS Release simulator build passes with the reviewed placeholder host.
- [x] All iOS unit tests pass with zero failures.
- [x] All backend tests pass with zero failures and no network access in the default suite.
- [x] Ruff lint and format checks pass; dependency checks pass.
- [ ] `git diff --check` passes once the directory is initialized as a Git repository.
- [ ] A release candidate completes a device-level smoke test against the selected backend.

## Known repository limitations

- The directory is not currently a Git worktree, so change-status and diff checks are unavailable.
- With the locally installed Xcode 26.5 toolchain, a generic iOS Simulator destination may fail
  during TCA macro expansion. Use a named simulator destination for local verification and recheck
  the generic/archive path with the distribution toolchain.
- Deployment, credentials, App Store metadata, legal review, and production provider attribution
  remain operator decisions outside this phase.

## Phase 12 verification record

On 2026-09-07, Xcode 26.5 built both Debug and Release for a named iPhone 17 Pro simulator running
iOS 26.5. All 101 iOS unit tests passed. The only emitted Xcode warning was the informational
AppIntents metadata skip because the target has no AppIntents dependency. The compiled Release
Info.plist contains version `1.0 (1)`, iOS 18 minimum, universal iPhone/iPad device family, the
reserved `https://api.example.com`, and no ATS exception.

A temporary iPhone SE (3rd generation) simulator was created, then removed after visual inspection.
The first-launch Dashboard rendered in standard light mode and dark Accessibility Large without
horizontal clipping; content remained in its native scrolling form. This does not replace a
physical-device, keyboard, or VoiceOver pass.

All 176 backend tests passed offline. Ruff lint/format and `pip check` passed. Alembic migrated a
fresh temporary SQLite database and a second `upgrade head` remained safely at
`20260905_0001 (head)`. Uvicorn started locally; `/health` returned `{"status":"ok"}` and `/ready`
returned `{"status":"ready","database":"not_required"}`. PostgreSQL migration/readiness and
deployed restart validation remain untested because no database/deployment is configured.

No CoinGecko or OpenAI live request was made: their keys and explicit live-call authorization are
absent. No staging or production host was deployed. No signed build or physical-device test was
possible because this Mac reports zero valid code-signing identities and no Apple team was
provided.

## Phase 12 release classification

### BLOCKERS

- No staging/production backend account, deployment, or real HTTPS hostname
- No staging/production PostgreSQL database, migration run, or database-backed `/ready` evidence
- No deployed E2E duplicate/restart idempotency result; multi-worker deployment must stay disabled
- No scheduled production retention cleanup or host log-collection verification
- No selected CoinGecko production plan/key or account-specific endpoint, quota, licensing, and
  attribution approval; no live six-asset smoke result
- Production OpenAI on/off decision is not recorded; if enabled, its key/model/live compatibility
  evidence is absent
- Bundle identifier remains `com.example.CryptoPortfolioAdvisor`
- Apple team, signing identities/profiles, signed archive, and physical-iPhone validation are absent
- Production AppIcon is missing
- Universal iPhone/iPad versus iPhone-only support is unresolved; iPad has not been manually tested
- Public privacy-policy and support URLs are absent
- App Store privacy answers, remaining metadata, screenshots, age rating, category, and App Store
  Connect record are unresolved
- Manual VoiceOver, hardware/software keyboard, actual network-condition, and install-over-install
  legacy-data checks are incomplete

### NON-BLOCKING POST-MVP TODOs

- Charts and additional visualization
- Exchange or wallet synchronization
- Push notifications and CloudKit
- Automatic trading (intentionally outside the product boundary)
- Advanced external observability beyond the selected host's standard logs
- Multi-worker scale after the documented PostgreSQL/lease tests pass; one worker is acceptable for
  the initial MVP

Current conclusion: **MVP repository-ready, deployment blocked.** Remaining work is release/operational
work or post-MVP backlog, not another architecture phase.
