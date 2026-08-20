# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.1.0
