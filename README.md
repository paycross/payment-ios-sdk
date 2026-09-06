# PayCross iOS SDK

Native iOS SDK for PayCross payments, mirroring [`payment-android-sdk`](https://github.com/paycross/payment-android-sdk).

## Installation

### CocoaPods

```ruby
pod 'PayCross', '~> 0.6.0'
```

### Swift Package Manager

```swift
.package(
    url: "https://github.com/paycross/payment-ios-sdk.git",
    .upToNextMinor(from: "0.6.0")
)
```

Add `PayCross` as a dependency of your app target. `PayCrossCore` comes along
transitively; depend on it directly only if you need its platform-agnostic
types (`Amount`, `PaymentResult`, `Recovery`, `PayCrossEnvironment`) without
the UI layer.

## Why the package is split in two

| Target | Contains | Builds on |
|---|---|---|
| `PayCrossCore` | payment state machine, validation, JWT decoding, wire models | **Linux and macOS** |
| `PayCross` | card form, 3DS web views, capture guards | macOS only |

This is not architectural taste. The SDK is developed from WSL2 with no Apple
hardware, and `mobile-mcp` cannot drive iOS simulators from Linux. Splitting on
the UIKit boundary means the majority of the SDK's behaviour is verified locally
in under a second, and only genuinely platform-bound code has to wait for CI.

`Sources/PayCrossCore` must never import UIKit, SwiftUI, WebKit or PassKit, and
every file in `Sources/PayCross` must open with `#if os(iOS)`. Both are enforced
by the `invariants` CI job, because the split is worthless the first time it
silently rots.

## Building

```sh
swift build
swift test
```

Requires Swift 6.0+. On Linux, install a toolchain from swift.org — no Xcode needed.

## Public API sketch

```swift
PayCrossAPI.configure(
    environment: .sandbox,
    applePayMerchantIdentifier: "merchant.example.com"
)

let sheet = PaymentSheet(sessionToken: token)
let result = await sheet.present(from: viewController)

switch result {
case .succeeded(let transactionID, _, let amount, let savedCardToken): …
case .failed(_, let recovery) where recovery.isRetryable: …
case .failed: …
case .pending(let transactionID, _): // Outcome unknown. Reconcile server-side before charging again.
case .cancelled(let transactionID): …
}
```

Shaped after the conventions merchants already know from Stripe, Adyen and
Braintree: configure once, construct a sheet with a session token, await a
result. Nothing throws — a decline is `.failed`, not a Swift `Error`, so the
happy path needs no `catch` and the compiler still checks the recovery branch.

`.pending` is the one outcome that deserves a second look. It means nobody saw a
verdict: the status poll ran out of time, or the server itself answered that it
cannot say. The payment may have succeeded and shifted liability, so it is
neither a success to fulfil on nor a decline to re-collect on — take the
transaction id, settle it against your own records, and only then decide. Its
`PendingReason` carries why, with raw values (`poll_timeout`, `result_lost`,
`server_verify`) shared verbatim with the Android SDK and the Flutter plugin, so
the same unresolved payment reads the same whichever platform reported it. This
SDK produces `poll_timeout` and `server_verify` only. `result_lost` belongs to
the Flutter plugin, whose result crosses a platform channel that can drop it; it
is in the shared vocabulary so that code handling pending outcomes handles it on
every platform, but nothing native ever emits it.

`savedCardToken` on `.succeeded` is the token for a card **this payment stored**,
and is nil whenever it stored none — the shopper left the save toggle off, paid
with a card already on file, or the session was already complete and had no
status to read one from. It is a handle on the stored card for a later payment,
useless anywhere but your own account, and it is the only place the token
appears: nothing else in the flow reports it.

## Appearance

The sheet takes a `PayCrossAppearance` at configure time. Everything on it is
optional, and a role left unset keeps the system colour the sheet already
draws, so an appearance that names one colour changes one colour.

```swift
PayCrossAPI.configure(
    environment: .production,
    appearance: PayCrossAppearance(
        light: PayCrossColors(brand: PayCrossColor(hex: "#1E88E5")),
        dark: PayCrossColors(brand: PayCrossColor(hex: "#64B5F6")),
        shapes: PayCrossShapes(cornerRadius: 16, buttonCornerRadius: 28)
    )
)
```

`PayCrossColor` takes components or a hex string. The hex initialiser is
failable and accepts `#RGB` and `#RRGGBB` only, with the hash, which is the
grammar the back office accepts and the Android SDK matches.

One brand colour and nothing else is a one-liner:

```swift
PayCrossAPI.configure(
    environment: .production,
    appearance: .brand(PayCrossColor(red: 0x1E, green: 0x88, blue: 0xE5))
)
```

### Precedence

Per role: **the appearance set in code wins, then the brand colour the merchant
set in the back office, then the platform default.** The server publishes a
brand colour only, and it applies to both appearances, because the branding
record holds no light/dark variants. So an integration that passes no
appearance at all still comes up in the merchant's own colour, and one that
sets `brand` overrides it.

A role set in one appearance and not the other is used in both. A partial
palette is a merchant changing one colour, not asking for the other appearance
to fall back to the system's.

### Roles

| Role | Where it lands |
|---|---|
| `brand` | Pay button fill, the selected stored-card radio, the sheet's tint |
| `onBrand` | Text and spinner on the Pay button. Unset derives it from `brand` |
| `surface` | The sheet's own background, and the 3DS challenge's |
| `component` | Inputs, stored-card rows, field groups |
| `componentBorder` | Their borders, drawn only when `borderWidth` is set |
| `text` | Primary text, including the card number and CVC |
| `textSecondary` | Field labels, the total's caption, card expiry, the brand badge |
| `placeholder` | Placeholder text in the card number, expiry and CVC fields |
| `icon` | The picker's radio and trash symbols |
| `error` | The error banner and field validation messages |

`onBrand` is computed from `brand`'s own luminance rather than from the
appearance: black above the WCAG crossover and white below it, which is the
same rule the Android SDK applies, so one brand colour reads the same on both
platforms. Set it yourself and the SDK does not argue.

### Theme mode

`themeMode` is `.system`, `.light` or `.dark`. A pinned mode applies to the
payment sheet's own window and to nothing else: the host app's appearance is
never touched.

Pin it if you set a `surface` for one appearance only. The navigation bar takes
the surface as its background but draws its title in the system's own colour
for the device's appearance, so a dark surface on a device in light mode gets a
dark title on it. Pinning the mode, or setting `surface` in both palettes,
avoids that.

### Shapes and the Pay button

`PayCrossShapes` carries `cornerRadius` (inputs, rows, groups, the error
banner; default 10), `buttonCornerRadius` (the Pay button and the Apple Pay
button; falls back to `cornerRadius`, then 12 and 10 respectively) and
`borderWidth`, which is null by default because the sheet draws no borders
today.

`PayCrossPrimaryButton` overrides the Pay button on its own: `background`,
`textColor`, `disabledBackground`, `disabledTextColor`, `cornerRadius` and
`height`. A merchant who overrides the fill and not the label gets the contrast
rule applied to the fill they chose, not to the brand they did not use.

### Type size

`PayCrossTypography(sizeScaleFactor:)` multiplies every font size on top of
Dynamic Type rather than instead of it. It is clamped to **0.8...1.3**, and the
size it multiplies is the shopper's own setting held at `accessibility3`, so the
two cannot compound past the ceiling the rest of the sheet respects. See
[Accessibility](#accessibility). A change made while the sheet is open is picked
up either way. A font family is not exposed in this release.

### Fixed by design

Not themable, and not by omission: the sheet's layout, spacing and insets; the
card-input internals; the Apple Pay button's colours, label and type, which are
Apple's to specify and a rejection to imitate; the 3DS page, which is the
issuer's own content; and the error copy, which is overridable as
[strings](#strings) rather than as appearance.

Deferred rather than refused: a merchant logo in the sheet, and a font family.
Both are the next appearance release, and the logo is a layout change rather
than a colour one.

## Saved cards

Which stored cards the sheet offers, and what it may do with them, is decided by
the session, not by the integration. `saved_cards` lists the cards, most recently
used first, and a sibling `saved_cards_config` block carries two flags:

```json
"saved_cards_config": { "allow_removal": true, "preselect": true }
```

Both default to off, and a session minted before the backend shipped the block
behaves as if both were false. Ask for them when you create the payment session.

- **`allow_removal`** puts a delete button on every stored row. Confirming it
  calls `DELETE saved-cards/{uuid}` with the session's own bearer token, and the
  row leaves the picker only once the server has answered — a card that vanishes
  on the tap and returns next session is worse than no button. The endpoint is
  idempotent, so removing a card twice is not an error. A 404 means the card is
  not this session customer's, which is the state the shopper asked for, so the
  row goes. A 401 means the session itself is finished and says so, because
  nothing is retryable on a dead token. Anything else leaves the row where it
  was and offers a retry. The delete button is not offered at all while a
  payment is being authorized.
- **`preselect`** opens the sheet with the most recently used card already
  picked, rather than on "Use a new card".

Preselection is a merchant opt-in for a reason, and the reason it is safe under
one is the CVC. A stored card on this sheet is never submittable on its own: the
shopper types its security code every time, whether they picked the card or the
session did. That is an issuer rule before it is a UX one, and it is what keeps a
preselected card from being one unnoticed tap away from a charge. The SDK does
not offer a way to turn it off.

## Deliberate divergences from Android

- **`Recovery` is not `RawRepresentable`.** A `String` raw value would synthesise
  `init?(rawValue:)`, a fail-*open* parser sitting next to the fail-closed one.
  Unknown server values become `.unrecognized(String)` — terminal, but with the
  raw value kept for telemetry, and non-source-breaking when a case is added.
- **The 3DS dedupe key sorts its data pairs.** Android interpolates a Kotlin
  `LinkedHashMap`, whose `toString()` is insertion-ordered. Swift `Dictionary`
  has no stable order, so a direct port would generate a different key for the
  same action and re-present the challenge mid-payment.
- **`CardValidator.isValidExpiry` takes its `now` as a parameter** rather than
  reading the clock, so year-boundary cases are testable.
- **`CardBrand.maxPANLength`** is 15 for Amex; Android bounds every PAN at 19.

## Strings and languages

The sheet ships **English and French**. Every user-visible string is looked up by
key — the merchant's bundle first, ours second — so defining one of these keys in
your app's `Localizable.strings` replaces our wording for that one label, and
defining none of them leaves the sheet as it comes. Every key is prefixed
`paycross_`, so nothing your app already names can collide with one: an override
happens because you asked for it, never by accident.

| Language | Tag |
|---|---|
| English | `en` |
| French | `fr` |

### Which language a shopper sees

Three sources, in order of preference:

1. `PayCrossAPI.configure(locale:)`
2. The session's `locale`, as the server sent it
3. The shopper's device preferences

They are matched one candidate at a time — exact tag first, then primary subtag,
so `fr-CA` is French — and the first naming a language the SDK ships wins. A
candidate it cannot speak is passed over rather than ending the search, so
`locale: "de"` falls through to the session's language and then the device's.
English when nothing matches. Nothing here throws.

```swift
PayCrossAPI.configure(environment: .sandbox, locale: "fr")
```

**The amount is not clamped to those two languages.** It is formatted in the
first tag the override or the session asks for, region intact, because Foundation
writes currency for every locale: `de-AT` gives Austrian digits under English
labels, and an `fr-CH` session gives French words with Swiss-French digits. A tag
that is not shaped like one is passed over here too, so a typo cannot misprint a
price.

When neither asks for anything the amount is formatted with the shopper's own
`Locale`, exactly as it was before the SDK spoke a second language. That carries
their Region and format settings, which the device's language list does not: an
`en_DE` phone shows `12,34 €` under English labels.

**An explicit locale does not turn string overrides off.** The two answer
different questions — which language, and which words — and your bundle is
searched first whatever the sheet resolved to. Your overrides come out in the
**sheet's** language: an app shipping English and French wording gives the French
to a French sheet even on an English phone.

[`LOCALIZATION.md`](LOCALIZATION.md) lists every key, what it paints, and which
of them carry a `%@` an override must keep.

## Test identifiers

Every element a UI test needs to reach carries an accessibility identifier, and
**the same string reaches it on Android**, where the matching Compose `testTag`
is published as a resource id. They are set in every build: an iOS
`accessibilityIdentifier` is not surfaced to VoiceOver or to other apps, so
there is nothing to gate. Android gates its tags on `FLAG_DEBUGGABLE`, and the
reason is a real one on that platform, so a release-build UI test can address
this sheet and not that one.

The strings are also constants, so a test can reference them rather than retype
them:

```swift
import PayCross

app.textFields[PayCrossTestIdentifiers.cardNumber.rawValue].tap()
app.buttons[PayCrossTestIdentifiers.savedCard(card.uuid)].tap()
```

| Element | Identifier |
|---|---|
| The sheet's content | `paycross.sheet` |
| Total | `paycross.amount` |
| Apple Pay button | `paycross.walletButton` |
| `Or pay with card` rule | `paycross.walletDivider` |
| Stored cards, as a container | `paycross.savedCards` |
| One stored card's row | `paycross.savedCard.<uuid>` |
| That row's delete button | `paycross.savedCard.<uuid>.delete` |
| `Use a new card` | `paycross.useNewCard` |
| Cardholder name | `paycross.cardholderName` |
| Card number | `paycross.cardNumber` |
| Detected brand | `paycross.brand` |
| Expiry | `paycross.expiry` |
| Security code | `paycross.cvv` |
| Save-card toggle | `paycross.saveCard` |
| A server-driven field | `paycross.field.<group>.<name>` |
| That field's validation message | `paycross.field.<group>.<name>.error` |
| Decline banner | `paycross.errorBanner` |
| Pay button | `paycross.payButton` |
| The spinner while the session loads | `paycross.loading` |
| 3-D Secure challenge | `paycross.threeDS` |
| Cancel, on the challenge | `paycross.threeDSCancel` |
| Done, above the numeric keypad | `paycross.keyboardDone` |
| `Yes, Cancel` | `paycross.cancelConfirm` |
| `Continue Payment` | `paycross.cancelDismiss` |
| `Remove` | `paycross.removeConfirm` |
| `Cancel`, in the delete confirmation | `paycross.removeDismiss` |

`<uuid>` is the card's own `uuid`, exactly as `saved_cards` listed it, so a test
can name a specific stored card without reading the screen first. `<group>` and
`<name>` come from `field_groups` the same way.

**The two confirmations have no identifier of their own**, only their buttons.
SwiftUI renders `.alert` as a `UIAlertController` this SDK never holds, so there
is nothing to name. Android's `paycross.cancelDialog` and `paycross.removeDialog`
have no iOS counterpart; assert on the buttons instead.

While a payment is in flight the spinner is inside the Pay button, which keeps
`paycross.payButton`. `paycross.loading` is the initial session fetch only.

## Accessibility

The floor this sheet is held to, and what holds it there.

- **Every control has a label.** The amount reads `Total, 25,99 €` rather than a
  bare number, composed from the caption above it, which is hidden from VoiceOver
  so it is not read twice. Each stored card's delete button is named after the
  row it belongs to.
- **The decline banner is announced.** VoiceOver reads what the shopper moves to,
  and a decline arrives without anyone moving, so it used to be silent. It also
  keeps its icon: the message is never colour alone.
- **Dynamic Type is honoured up to `accessibility3`, and clamped there.** Layouts
  stack rather than clip: the expiry and the security code sit one above the
  other at accessibility sizes, and both buttons grow with their labels. Above
  `accessibility3` the sheet stops growing, because a form whose Pay button is
  off the bottom of the screen is one nobody can pay on.
- **A merchant size factor is multiplied against a size that has already been
  clamped**, so `sizeScaleFactor` and the shopper's setting cannot compound past
  that ceiling. Under it, the factor still tracks the shopper's setting exactly
  as before.
- **Touch targets are at least 44pt.** The card fields were 22pt controls
  centred in 46pt boxes: the padding around a text field is not part of it, and a
  tap that landed there focused nothing. Every field now fills its box, and the
  two SwiftUI-backed ones hand the focus on from a tap anywhere in the box.

Verified by `AccessibilityFloorTests` on real renders, and by the
`23-accessibility-ceiling` and `24-french-accessibility-ceiling` screenshots that
CI uploads on every push.

## Apple Pay

### What the SDK does

When the session allows the wallet, an Apple merchant identifier is configured
and the device has a card it can pay with, the payment sheet renders Apple's own
`PKPaymentButton` above the card form. Tapping it presents Apple's sheet,
authorizes, and submits the resulting payment token to PayCross as
`payment_method: "apple_pay"`, resolving to the same `PaymentResult` as a card
payment. The host app adds no view, makes no call, and implements no delegate.

If any of the three conditions is unmet there is simply no button and the card
form behaves exactly as it did before. In particular, `canMakePayments(usingNetworks:)`
is false on a simulator with an empty Wallet, so the button does not appear
there; Apple Pay can only be exercised on a real device with a provisioned card.

### What the merchant does

Six steps, and skipping them leaves the card form only — nothing breaks.

1. Ask PayCross to enable Apple Pay for your merchant account.
2. Download PayCross's Apple Pay certificate request (`.csr`) from the back
   office. It is the same file for every merchant in that environment.
3. In your own Apple Developer team, create a Merchant ID, upload that
   certificate request, and let Apple issue the payment-processing certificate.
4. Tell PayCross the Merchant ID, in the back office's Apple merchant identifier
   field. PayCross cannot derive it, and the vault cannot decrypt a payment
   token without it.
5. In Xcode, add the Apple Pay capability to the app id and tick that Merchant
   ID. This is what puts the identifier into the app's
   `com.apple.developer.in-app-payments` entitlement.
6. Pass the same string to `configure`, as `applePayMerchantIdentifier`.

### The one failure worth naming

The identifier passed to `configure` and the identifier on the merchant record
must be the same string. Apple hashes it into the key that encrypts every
payment token, so when the two disagree nothing downstream can decrypt what the
device produced. PayCross refuses such a payment at the edge and returns a
sentence saying so, which the sheet shows inline. When the SDK has no identifier
at all there is no button, and no payment to refuse.

## App Store privacy labels

Both pods ship a `PrivacyInfo.xcprivacy` manifest (Apple has required this
since spring 2024; without one, merchants get an App Store Connect warning
or outright rejection on submission). For a merchant filling out their own
app's privacy label, here is what the SDK actually does:

- **Collects, for app functionality, linked to the identity of the payer:**
  card data (number, expiry, CVC), cardholder name, and — only when the
  session config surfaces those fields — email address and phone number.
  This data is entered in `PayCross`'s UI and transmitted by `PayCrossCore`
  to the PayCross backend to process the payment; it is not used for
  advertising or shared with data brokers. An Apple Pay payment is still
  payment data for labelling purposes, but no card number is ever entered or
  seen: the SDK forwards Apple's encrypted payment token unread, and what the
  backend decrypts from it is a device account number — a number Apple issues
  for that card on that device — rather than the shopper's own card number.
- **Tracking: no.** `NSPrivacyTracking` is `false` in both manifests, and
  neither pod contacts any tracking domain.
- **IP address is not collected client-side.** The SDK does not read or
  transmit the device's IP address; the backend derives it server-side from
  the connection (Cloudflare connecting-IP header, falling back to source
  IP). Merchants do not need to declare IP collection on the SDK's behalf.

Merchants should reflect card data, name, email and phone (as applicable to
their session configuration) in their own App Store privacy label as data
"used to track you: No" / "linked to you: Yes" / "app functionality."

## Known documentation defects in the Android repo

Found while porting; the Kotlin is correct and the docs are not:

- `docs/DESIGN.md:174` describes abandoned exponential-backoff polling (1s→5s,
  60 attempts). `docs/API.md:421` says "every 3 seconds". `PaymentViewModel.kt:365`
  actually ships fixed 2000 ms interval, 480 s deadline, 5 submit attempts.
  **This port follows the code.**
