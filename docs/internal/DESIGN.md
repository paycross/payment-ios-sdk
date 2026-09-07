# Design notes

Maintainer notes for the PayCross iOS SDK. Merchant-facing documentation is
the developer portal, at <https://docs.pay-cross.com/guides/ios/>; what follows
is here because it is about the repository rather than the integration.

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

