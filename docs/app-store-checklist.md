# App Store submission inputs

Do not submit until each value is supplied and verified against the signed build and deployed data
flow. Blank values are intentional; this repository does not invent product, legal, or account
metadata.

## Product page

- App name: **TBD**
- Subtitle: **TBD**
- Description: **TBD**
- Keywords: **TBD**
- Primary/secondary category: **TBD**
- Age rating questionnaire: **TBD**
- Availability/territories: **TBD**
- Copyright/rights holder: **TBD**
- Support URL: **TBD**
- Marketing URL, if used: **TBD**
- Public privacy policy URL: **TBD — release blocker**
- Review contact and review notes: **TBD**

## Build and media

- Final bundle identifier/App Store Connect record: **TBD — release blocker**
- Apple team, distribution certificate, and profile: **TBD — release blocker**
- Marketing version/build: currently `1.0 (1)`; confirm and increment build for each uploaded binary
- Final AppIcon asset catalog: **missing — release blocker**
- Supported device family/orientations: currently universal iPhone/iPad without explicit orientation
  keys; product decision and iPad validation are pending
- Screenshots for every selected device class: **TBD**
- Signed archive validation and physical-iPhone smoke: **TBD — release blocker**

## Privacy and provider review

- App Privacy answers based on [`privacy-data-flow.md`](privacy-data-flow.md) and deployed host facts:
  **TBD — release blocker**
- Privacy manifest/dependency review: the current unsigned Release bundle contains the TCA and
  swift-sharing manifests, each declaring no collection/tracking and their required-reason API use.
  TCA is not named on Apple's current mandatory third-party SDK list. Generate Xcode's aggregated
  privacy report and revalidate the final signed archive before upload: **final gate pending**
- OpenAI enabled in production: **TBD**
- CoinGecko production plan, license, quota, attribution, and approved wording: **TBD — release
  blocker**
- Visible analytical/no-trading/volatility/user-responsibility disclaimer: **implemented; verify in
  the release candidate**

## Accessibility and review workflow

- VoiceOver pass on Dashboard, History, and Analysis Details: **TBD**
- Small-device, light/dark, accessibility Dynamic Type: repository simulator pass recorded
- Hardware/software keyboard financial-entry pass: **TBD**
- Reviewer workflow against the production backend: **TBD**
- Explain that the app analyzes manual entries and cannot execute trades; do not promise returns or
  present it as an exchange/wallet

## Version/build procedure

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are centralized in the app target build settings.
Keep `MARKETING_VERSION=1.0` for the intended first release unless product direction changes. Before
each App Store Connect upload, increment `CURRENT_PROJECT_VERSION` to a unique positive integer,
build the archive, and verify both values in the archived app's Info.plist. Do not increment merely
for local simulator tests.
