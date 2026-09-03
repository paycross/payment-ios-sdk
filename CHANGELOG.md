# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-09-03

### Changed

- The Apple Pay button is offered on account-funding sessions. `account_funding`
  marks a session as an account-funding transfer, and the backend now accepts a
  wallet payment on one and forwards the transfer to the acquirer as an AFT, so
  the flag no longer hides the button. `wallets.apple_pay: false` is still the
  only refusal, and the transfer's sender and recipient fields are still
  collected from `field_groups` before the sheet opens.

## [0.2.0] - 2026-09-02

### Added

- Apple Pay inside the payment sheet, gated by the session's `wallets` block and
  the merchant's Apple merchant identifier. Apple's own button is rendered above
  the card form when the session allows the wallet, an identifier is configured
  and the device has a card it can pay with; the host app adds no view and makes
  no call.
- `applePayMerchantIdentifier` on `PayCrossAPI.configure`, defaulting to nil.
  Without it there is no Apple Pay button, which is the correct default: Apple
  hashes the identifier into the key that encrypts every payment token, so a
  token produced without the merchant's own identifier cannot be decrypted.

### Fixed

- The User-Agent reported `0.1.0-alpha` on every release since 0.1.0.

## [0.1.1] - 2026-08-28

### Fixed

- A 3-D Secure challenge no longer traps the shopper. The challenge is added over
  the whole payment sheet, toolbar included, so it covered the sheet's only
  Cancel button: a shopper who wanted to abandon a challenge could not, and was
  held until the 480s poll deadline turned the payment into
  `.failed(recovery: .retry)` instead of `.cancelled`. A challenge now carries a
  Cancel of its own, above the issuer's page, which runs the same two-step
  "Cancel Payment?" confirmation as the sheet's.
- A challenge is now marked as an accessibility modal, so VoiceOver stays inside
  it. It previously read out — and could operate — the card form underneath.

## [0.1.0] - 2026-08-20

Initial public release.

### Added

- Card payment and 3D Secure v2 flows: card entry, saved cards, status
  polling, and challenge presentation, resolving to a single `PaymentResult`.
- Privacy manifests (`PrivacyInfo.xcprivacy`) shipped in both pods.
- `PayCrossCore`, the platform-agnostic core (state machine, wire models, JWT
  decoding, card validation, 3DS navigation rules), publishable and testable
  independently of the UI layer.

### Changed

- `browser_info.language` is clamped to a backend-safe BCP-47 prefix before
  being sent with a card submission.
- The device's public IP address is no longer read or transmitted by the SDK;
  the backend derives it server-side from the connection instead.
- `PayCrossCore`'s public API surface is restricted to the four
  merchant-facing types; internal collaborators moved to package access.
- The payments client no longer caches status poll responses.

[Unreleased]: https://github.com/paycross/payment-ios-sdk/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.2.1
[0.2.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.2.0
[0.1.1]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.1.1
[0.1.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.1.0
