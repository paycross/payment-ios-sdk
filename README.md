# PayCross iOS SDK

Native iOS SDK for PayCross payments, mirroring [`payment-android-sdk`](https://github.com/paycross/payment-android-sdk).

## Installation

### CocoaPods

```ruby
pod 'PayCross', '~> 0.1'
```

### Swift Package Manager

```swift
.package(url: "https://github.com/paycross/payment-ios-sdk.git", from: "0.1.0")
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
PayCrossAPI.configure(environment: .sandbox)

let sheet = PaymentSheet(sessionToken: token)
let result = await sheet.present(from: viewController)

switch result {
case .succeeded(let transactionID, _, let amount): …
case .failed(_, let recovery) where recovery.isRetryable: …
case .failed: …
case .cancelled: …
}
```

Shaped after the conventions merchants already know from Stripe, Adyen and
Braintree: configure once, construct a sheet with a session token, await a
result. Nothing throws — a decline is `.failed`, not a Swift `Error`, so the
happy path needs no `catch` and the compiler still checks the recovery branch.

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
- **Apple Pay is deferred past v1**, despite the backend supporting it
  (`payment_method: "apple_pay"`), because a merchant ID is gated behind the
  Apple Developer Program and PassKit authorization cannot be exercised on a
  simulator.

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
  advertising or shared with data brokers.
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
