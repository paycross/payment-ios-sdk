# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The API reference is generated from the source on the release tag and
  published as a release asset, `paycross-ios-reference.zip`, which the
  developer portal serves at
  <https://docs.pay-cross.com/reference/ios/paycross/documentation/paycross/>.

## [0.7.1] - 2026-09-07

### Fixed

- **A container no longer takes its children's test identifiers.** An
  accessibility identifier on a container is inherited by every descendant that
  is not already inside an element of its own, and the container's string wins,
  so 0.7.0 published `paycross.sheet` on the Pay button and on the initial
  spinner, and `paycross.savedCards` on every stored-card row, every delete
  button and `Use a new card`. The README's own
  `app.buttons[PayCrossTestIdentifiers.payButton.rawValue]` example matched
  nothing. The two containers are now accessibility containers, so they keep
  their own name and their children keep theirs. A UI test that worked around
  this by addressing `paycross.sheet` or `paycross.savedCards` and reading down
  from there must go back to the names in the
  [table](https://docs.pay-cross.com/guides/ios/test-identifiers/). **Both names also change element type**:
  each now lands on a container element of its own rather than on the view it
  happened to settle on, so `paycross.sheet` is `app.otherElements[...]` where it
  used to answer as the sheet's scroll view.
- **A server-driven field's validation message answers to its own identifier.**
  The same defect one level down: the column carried
  `paycross.field.<group>.<name>` and replaced the message's
  `paycross.field.<group>.<name>.error` with it. The field identifier moves onto
  the input box, which is where Android tags it, so the box and the message are
  two elements with two names. `app.textFields[...]` for a field is unchanged.
  The label drawn above a field inherited the field's identifier in 0.7.0 and no
  longer does, so a test matching it as `app.staticTexts[...]` must address the
  box instead.
- **The device language rung reads the shopper's list rather than the host
  app's.** `Locale.preferredLanguages` answers with the shopper's languages
  intersected with the host app's localizations, so a merchant app shipping only
  `Base.lproj` never got the French sheet on a French phone even though the SDK
  ships French. The rung now reads `AppleLanguages`, the raw ranked list. An app
  that sets that key in its own defaults to offer an in-app language switch
  still decides. `PayCrossCore`'s privacy manifest declares the read as
  `CA92.1`.

## [0.7.0] - 2026-09-06

### Changed — source-incompatible, and the next release is a MINOR bump

- **Every test identifier is renamed.** Twelve flat names become
  `paycross.`-prefixed camelCase ones, and `paycross.savedCard.new` becomes
  `paycross.useNewCard`, which is the name Android already used. A UI test
  matching any of the old strings stops finding its element — silently, the way
  a UI test does. The full table is in the
  [the portal](https://docs.pay-cross.com/guides/ios/test-identifiers/); the old names are `amount`,
  `applePayButton`, `cardNumber`, `expiry`, `cvv`, `cardholderName`, `brand`,
  `errorBanner`, `payButton`, `threeDSCancel`, `keyboardDone` and
  `field-<name>`. Nothing keeps them: half a sheet under one scheme and half
  under another is worse than either.
- `PayCrossAPI.configure` gains a fifth parameter, `locale: String?`, defaulted
  to nil and added last, so a call that uses argument labels keeps compiling
  untouched. What does not: a reference to `configure` as a function value, and
  anything binding `Configuration` positionally, which now carries a `locale` of
  its own. The same break 0.6.0 took for `appearance`.

### Added

- **`PayCrossTestIdentifiers`**, the identifier strings as constants, so a
  merchant's UI test can reference them rather than retype them. Same strings on
  both platforms, including `savedCard(_:)` keyed by the card's own `uuid`.
  Fourteen elements that had no handle at all now have one: the sheet root, the
  sheet's own Cancel, the save-card toggle, the wallet divider, the stored-card
  container, server-field validation messages, the initial spinner, the 3-D
  Secure challenge, and both confirmations with their two buttons each.
- **An announced decline.** The error banner posts an accessibility
  announcement when it appears and when its wording changes, so a shopper using
  VoiceOver hears why the payment stopped instead of only noticing the Pay
  button go quiet.
- **A label on the amount**, reading `Total, 25,99 €` rather than a bare number.
  Composed from the caption above it, which is now hidden from VoiceOver so it
  is not read twice.
- **An accessibility floor**, documented in the
  [the portal](https://docs.pay-cross.com/guides/ios/accessibility/): every control labelled, Dynamic Type
  honoured to `accessibility3`, layouts that stack rather than clip, and 44pt
  touch targets. One surface stays outside it and says so: the 3-D Secure
  challenge, whose page is the issuer's own web content.
- **French.** The sheet ships `fr` alongside `en`, 32 keys each. See
  [`LOCALIZATION.md`](https://github.com/paycross/payment-ios-sdk/blob/main/LOCALIZATION.md) for every key, what it paints, and which
  carry a `%@`.
- **A rule for which language a shopper sees.** `configure(locale:)`, then the
  session's `locale`, then the device's preferences in order. Candidates are
  matched one at a time — exact tag first, then primary subtag (`fr-CA` → `fr`) —
  and the first naming a language the SDK ships wins. One it cannot speak is
  passed over rather than ending the search, so `locale: "de"` falls through to
  the session's language. English when nothing matches. Case-insensitive; `_`
  accepted for `-`; nothing throws.
- The three Apple Pay failure messages, the three flow errors and the two
  field-validation fallbacks are now keys rather than literals, so all eight are
  translatable and overridable like the rest.

### Changed

- **The cancel and delete confirmations are drawn by the SDK** instead of being
  raised as system alerts. They keep their copy, their two-step shape and their
  destructive-first ordering; what changes is that they are addressable.
  SwiftUI renders `.alert` through a `UIAlertController` and does not carry a
  button's identifier onto the resulting action — measured on iOS 26.5, both
  actions came back with a nil identifier and the alert's view tree carried
  none — so neither dialog nor any of their four buttons could be reached by
  name. The two answers stack rather than sitting side by side, because
  `Continue Payment` already wraps beside `Yes, Cancel` on a 390pt sheet and
  `Continuer le paiement` is longer still. Each one announces itself to
  VoiceOver and takes focus onto its own title, which the system alert did for
  free and a plain view does not do at all.
- **Dynamic Type is clamped at `accessibility3`**, and a merchant's
  `sizeScaleFactor` now multiplies a size that has already been clamped rather
  than compounding with the shopper's setting. Below the ceiling nothing about
  the factor changes. Above it the sheet stops growing, which is the trade that
  keeps the Pay button on the screen.
- **The expiry and the security code stack vertically at accessibility sizes**
  instead of sharing a row and shrinking to slivers.
- **Both buttons grow with their labels.** The Apple Pay and Pay button heights
  scale with Dynamic Type, and a merchant-pinned `buttonHeight` is honoured as a
  minimum rather than as a fixed height. A merchant who pinned a height taller
  than the default now gets it on the Apple Pay button too, which previously
  ignored it.
- **The card fields are touch targets.** They were 22pt controls centred in 46pt
  boxes, so a tap in the padding focused nothing. Each field fills its box now;
  the boxes are 2pt shorter and otherwise unchanged.
- The amount is formatted in the first tag anybody **asked for** — the override,
  else the session — with its region intact, provided it is shaped like a
  language tag. It is not clamped to the two languages the SDK ships, so a
  merchant asking for `de-AT` gets Austrian digits under English labels. When
  neither names one, the amount is formatted with `Locale.current` exactly as it
  was in 0.6.0: the device's language list carries no region and none of the
  shopper's format settings, so it is not used to rebuild a locale.
- Merchant string overrides are resolved in the **sheet's** language rather than
  the device's. An app shipping English and French overrides now gives the French
  ones to a French sheet on an English phone, where before it gave the English
  ones and produced a half-translated sheet.
- Three English values change. The keys do not — keys are public API through the
  string override.
  - `paycross_save_this_card`: `Save this card` → `Save card for future use`,
    matching Android and the hosted checkout page. The key still reads
    `save_this_card`; it is not renamed.
  - `paycross_or_pay_with_card`: `or pay with card` → `Or pay with card`. It is a
    standalone caption between two rules, and both other surfaces use sentence
    case. The caption no longer wraps: the divider lines give instead.
  - `paycross_remove_card_message`: `It will no longer be offered for future
    payments.` → `%@ will no longer be offered for future payments.`, naming the
    card being removed.
- **`paycross_remove_card_message` now takes a format argument where it had
  none.** A merchant overriding that key must include a `%@`, or the alert will
  not say which card it is about to remove.
- iOS captions the amount with `paycross_total` and Android does not. The two
  sheets are deliberately asymmetric here.

### Internal

- Placeholders are filled by substituting a literal `%@` rather than by
  `String(format:)`, on both sides of the Core/UI split. These templates can come
  from a merchant's own strings file, and `String(format:)` handed a mistyped
  `%d` reads a vararg that was never passed. A bad override now costs a label
  with a `%d` in it and nothing more.
- `PayCrossCore` no longer hard-codes the sentences it shows. `FlowMessages`
  carries them in, defaulted to the English the SDK already shipped, so the
  runner's actor isolation holds and every Core test still asserts prose.

## [0.6.0] - 2026-09-06

### Changed — source-incompatible, and the next release is a MINOR bump

- `PayCrossAPI.configure` gains a fourth parameter, `appearance:
  PayCrossAppearance?`, defaulted to nil and added last, so a call that uses
  argument labels keeps compiling untouched. What does not: a reference to
  `configure` as a function value, and anything binding `Configuration`
  positionally, which now carries an `appearance` of its own.

### Added

- `PayCrossAppearance`: colours per appearance, a theme mode, corner radii, a
  border width, Pay button overrides and a type size factor. Ten colour roles —
  `brand`, `onBrand`, `surface`, `component`, `componentBorder`, `text`,
  `textSecondary`, `placeholder`, `icon`, `error` — each nullable, each falling
  back to the system colour the sheet already drew, so an appearance that names
  one colour changes one colour and an empty one changes nothing.
  `PayCrossAppearance.brand(_:)` is the whole thing for a merchant who only
  wants their own accent.
- The brand colour a merchant sets in the PayCross back office now reaches the
  sheet with the session, as a `branding` block on the session data, and is
  used as the default `brand` in both appearances. Precedence per role is: the
  appearance set in code, then the server's brand colour, then the platform.
  An integration that passes no appearance at all comes up in the merchant's
  own colour. Sessions minted before the backend shipped the block carry none,
  and a colour the SDK cannot read costs the accent and nothing else.
- `themeMode` pins the sheet to light or dark against the device. It applies to
  the payment sheet's own window; the host app's appearance is never touched.
- `PayCrossColor`, a platform-free ARGB colour with a `#RGB` / `#RRGGBB` /
  `#AARRGGBB` initialiser. It lives in `PayCrossCore` so the rules that decide
  what the sheet draws are tested on Linux rather than only on a simulator.
- A debug-build warning when a resolved brand or Pay button pair falls under the
  4.5:1 contrast minimum. Reported, never corrected, and never in a release
  build.

### Fixed

- The Pay button drew its label and its spinner in white over the app's accent
  colour, so on a light accent the amount vanished on the one control the
  shopper has to press. The label now follows the fill's own luminance, by the
  same rule the Android SDK applies, and answers light and dark separately when
  the accent differs between them.

## [0.5.0] - 2026-09-05

### Changed — source-incompatible, and the next release is a MINOR bump

- `PaymentResult.succeeded` gains a fourth associated value,
  `savedCardToken: String?`, so a `case .succeeded(let id, let status, let amount)`
  in merchant code no longer compiles until it binds or ignores the new one. It
  carries the token for a card *this payment* stored and is nil whenever the
  payment stored none — the save toggle was off, the shopper paid with a card
  already on file, or the session resolved as complete with no status to read
  one from. Nothing else in the flow ever reported it, so a merchant who offers
  "save this card" had no way to learn the token from the SDK at all.

### Added

- Saved-card removal, driven by the session. A new `saved_cards_config` block
  beside `saved_cards` carries `allow_removal`, which puts a delete button on
  every stored row; confirming it calls `DELETE saved-cards/{uuid}` with the
  session bearer, and the row leaves the picker only once the server has taken
  the card. The endpoint is idempotent, so a repeated removal is a success; a 404
  means the card is not this session customer's and the row goes; a 401 reports
  the finished session rather than blaming the card; anything else leaves the row
  and offers a retry. The button is not offered while a payment is being
  authorized.
- `saved_cards_config.preselect`, a merchant opt-in that opens the sheet with the
  most recently used stored card already picked instead of "Use a new card". Safe
  under an opt-in because a stored card still needs its CVC on every payment: no
  single tap on this sheet can charge one. Both flags default to off, and a
  session minted before the backend shipped the block reads as both off.
- Six strings keys, overridable the same way as the rest: `paycross_remove_card`
  (the delete button's VoiceOver label, interpolating the row it belongs to, so
  an override has to keep its `%@`), `paycross_remove_card_title`,
  `paycross_remove_card_message`, `paycross_remove_card_confirm`,
  `paycross_remove_card_failed` and `paycross_session_expired`.

## [0.4.0] - 2026-09-05

### Added

- `defaultLocalization: "en"` on the package and an English `Localizable.strings`
  shipped inside the SDK's own bundle, so the sheet's copy travels with the SDK
  under both Swift Package Manager and CocoaPods.
- A deliberate way to reword the sheet. Every user-visible string is looked up by
  a `paycross_`-prefixed key, merchant bundle first, so an app that defines one of
  those keys in its own `Localizable.strings` gets its own wording, and an app
  that defines none of them gets ours. The prefix is what makes the override
  deliberate: no string an app already names collides with one of ours, so
  rewording a label takes naming the key on purpose. The keys are in the README.

### Changed — source-incompatible, and the next release is a MINOR bump

- `PaymentResult` gains a `pending(transactionID:, reason: PendingReason)` case,
  so an exhaustive `switch` over a result in merchant code will no longer compile
  until it handles the new value. It is the outcome nobody observed — the status
  poll ran out of time, or the server itself answered `verify_before_retry` — and
  the payment may have succeeded and shifted liability, so it is neither a success
  to fulfil on nor a decline to re-collect on. Reconcile the transaction id
  server-side before charging again: this is the one outcome where retrying can
  charge a shopper twice, and reporting it as a failure is what invited that.
  `PendingReason` says which of the two produced it (`poll_timeout`,
  `server_verify`; `result_lost` is in the vocabulary for the Flutter plugin and
  is never produced natively), and its raw values match the Android SDK and the
  plugin exactly. `Recovery.verifyBeforeRetry` remains in the enum and is still
  parsed off the wire, but no `.failed` result carries it any more, so merchant
  code that branched on it moves to `.pending`.

### Fixed

- A merchant app can no longer repaint the payment sheet's labels by accident. A
  SwiftUI `Text("Card Number")` inside a package resolves that literal as a
  lookup key against `Bundle.main` — the merchant's app — and not against the
  package's own bundle, so any host app whose `Localizable.strings` happened to
  define one of our English labels silently replaced our copy with theirs, and an
  app localized into a language the SDK does not ship could render the sheet in a
  mix of the two. Nothing announced this: the sheet simply came up wrong. Lookups
  now resolve in the SDK bundle under keys of ours that an app cannot name by
  chance, so an override has to be asked for to happen.

## [0.3.0] - 2026-09-04

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

[Unreleased]: https://github.com/paycross/payment-ios-sdk/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.7.1
[0.7.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.7.0
[0.6.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.6.0
[0.5.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.5.0
[0.4.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.4.0
[0.3.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.3.0
[0.2.1]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.2.1
[0.2.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.2.0
[0.1.1]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.1.1
[0.1.0]: https://github.com/paycross/payment-ios-sdk/releases/tag/v0.1.0
