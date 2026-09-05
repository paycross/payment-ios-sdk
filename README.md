# PayCross iOS SDK

Native iOS SDK for PayCross payments, mirroring [`payment-android-sdk`](https://github.com/paycross/payment-android-sdk).

## Installation

### CocoaPods

```ruby
pod 'PayCross', '~> 0.4.0'
```

### Swift Package Manager

```swift
.package(
    url: "https://github.com/paycross/payment-ios-sdk.git",
    .upToNextMinor(from: "0.4.0")
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

## Strings

The sheet ships English, in the SDK's own bundle. Every user-visible string is
looked up by key — the merchant's bundle first, ours second — so defining one of
these keys in your app's `Localizable.strings` replaces our wording for that one
label, and defining none of them leaves the sheet as it comes. Every key is
prefixed `paycross_`, so nothing your app already names can collide with one:
an override happens because you asked for it, never by accident. Localizing the
sheet into another language is the same mechanism: supply the keys you want, in
your app's `.lproj` for that language.

```
"paycross_or_pay_with_card"         = "or pay with card";
"paycross_cardholder_name"          = "Cardholder Name";
"paycross_name_on_card"             = "NAME ON CARD";
"paycross_card_number"              = "Card Number";
"paycross_expiry_label"             = "MM/YY";
"paycross_cvv"                      = "CVV";
"paycross_save_this_card"           = "Save this card";
"paycross_use_a_new_card"           = "Use a new card";
"paycross_total"                    = "Total";
"paycross_pay_amount"               = "Pay %@";
"paycross_payment"                  = "Payment";
"paycross_cancel"                   = "Cancel";
"paycross_cancel_payment_title"     = "Cancel Payment?";
"paycross_cancel_payment_yes"       = "Yes, Cancel";
"paycross_cancel_payment_continue"  = "Continue Payment";
"paycross_cancel_payment_message"   = "Are you sure you want to cancel this payment?";
"paycross_apple_pay_not_configured" = "Apple Pay is not configured for this merchant.";
"paycross_keyboard_done"            = "Done";
"paycross_remove_card"              = "Remove card, %@";
"paycross_remove_card_title"        = "Remove this card?";
"paycross_remove_card_message"      = "It will no longer be offered for future payments.";
"paycross_remove_card_confirm"      = "Remove";
"paycross_remove_card_failed"       = "Could not remove the card. Try again.";
"paycross_session_expired"          = "This payment session has expired. Start again.";
```

`paycross_pay_amount` interpolates the formatted amount and
`paycross_remove_card` the row the delete button belongs to, so an override of
either has to keep its `%@`. The placeholders shown inside the card number and expiry fields,
and the dash standing in for an unmade selection, are shape hints rather than
copy, and are not overridable.

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
