# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The transaction id on a cancellation. A payment cancelled mid-authorization may
  still complete server-side, and after a decline-then-cancel or a cancel during a
  3-D Secure challenge the merchant was left with a transaction in `failed` or
  `threeds_challenge_requested` that the host app had no way to correlate. It is
  nil when the sheet is dismissed before a transaction exists.

### Changed — source-incompatible, and the next release is a MINOR bump

- `Recovery` gains a `verifyBeforeRetry` case, so an exhaustive `switch` over
  `Recovery` in merchant code will no longer compile until it handles the new
  value. Handle it as terminal: `isRetryable` is false for it, so code branching
  on `isRetryable` rather than on the case needs no change.
- `PaymentResult.cancelled` carries the last transaction this session created, as
  `cancelled(transactionID: String?)`. A `case .cancelled:` pattern keeps
  compiling; constructing `.cancelled` and comparing against it do not, and become
  `.cancelled(transactionID: nil)`.

### Fixed

- The payment sheet no longer waits on WebKit before showing its form. The user
  agent the ACS fingerprints against is read out of a `WKWebView`, and that read
  was awaited before the session was fetched, so on a device whose WebKit is slow
  to start the sheet sat on its spinner — and where WebKit never came up, it stayed
  there. The read now starts with the sheet and is collected at submit instead,
  where it is bounded at two seconds and falls back to a static agent. A shopper
  spends far longer than that entering a card, so a healthy device is unaffected.
- A saved American Express card can have its 4-digit CID entered. The saved-card
  path forced the CVV brand to `.unknown`, capping the field at three digits, so
  a correct CID never validated and the Pay button stayed disabled: the card was
  unusable once saved. The stored brand now governs the field's length.
- The numeric keypad the card fields raise can be dismissed. `numberPad` has no
  Return key and iOS attaches no accessory to it, so the pad covered the lower
  third of the sheet with nothing on screen that would put it away. The card
  number, expiry and CVV fields now carry a Done button above the keypad, a drag
  down the form dismisses it, and so does a tap off the fields.
- The card form's keypad no longer follows the shopper onto a 3-D Secure page.
  The CVV field was still first responder when the flow left the form, so its
  keypad stayed up over the lower third of the challenge, where the issuer's own
  buttons sit. After a device rotation nothing would close it. Editing now ends
  as a 3-D Secure step is presented.
- A form re-armed after a retryable decline is bounded by the session's own
  lifetime. The 480 s poll deadline ends with the poll it belongs to, so nothing
  bounded the re-armed sheet: it could sit on a live Pay button long after the
  session had expired server-side, and the shopper's next tap could only fail.
  A decline that arrives on an already-expired session now resolves as
  `.failed(recovery: .restart)`, and a sheet whose session expires while the form
  waits resolves the same way.
- The decline banner is drawn where the shopper can see it. It was the last item
  in the scrolling column, so on a form carrying server-driven field groups it
  landed off the bottom of the screen: after a retryable decline the shopper saw
  an unchanged form and a Pay button that had gone disabled, with no reason given
  for either. It now sits directly under the total.
- A declined Apple Pay payment no longer wipes a CVV the shopper had already
  typed into the card form. All three wallet decline routes used the card path's
  decline event, which clears the CVV because PCI DSS 3.3.1 forbids retaining it
  after authorization. A wallet payment carries a payment token, so the card on
  the form was never authorized and there is nothing to discard. Deferred from
  0.2.0.
- The status poll no longer reports a retryable failure when it runs out of time.
  A payment whose outcome the SDK never observed may have succeeded and shifted
  liability, and `.retry` invited the merchant to re-collect it. The deadline now
  resolves as `.failed(transactionID:, recovery: .verifyBeforeRetry)`, meaning
  check this transaction's status before charging again. The transaction id was
  already carried and is what resolves the outcome out of band. `verify_before_retry`
  is also accepted from the server, matching the Android SDK.

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
