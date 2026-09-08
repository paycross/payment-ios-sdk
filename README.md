# PayCross iOS SDK

Card payments, 3-D Secure v2, saved cards and Apple Pay for iOS, as a drop-in
sheet. Your app hands it a payment session token and gets a result back.

## Install

### CocoaPods

```ruby
pod 'PayCross', '~> 0.7.2'
```

### Swift Package Manager

```swift
.package(
    url: "https://github.com/paycross/payment-ios-sdk.git",
    .upToNextMinor(from: "0.7.2")
)
```

Add `PayCross` to your app target; `PayCrossCore` comes along transitively.
Requires iOS 16 and Swift 6.

## Quickstart

```swift
PayCrossAPI.configure(environment: .production,
                      applePayMerchantIdentifier: "merchant.example.com")

let sheet = PaymentSheet(sessionToken: token)
switch await sheet.present(from: viewController) {
case .succeeded(let transactionID, _, _, let savedCardToken): …
case .failed(_, let recovery) where recovery.isRetryable: …
case .failed: …
case .pending(let transactionID, _): … // Outcome unknown. Reconcile server-side.
case .cancelled(let transactionID): …
}
```

## Documentation

- **[iOS guide](https://developers.pay-cross.com/guides/ios/)** — appearance, languages,
  saved cards, Apple Pay, test identifiers, accessibility and privacy labels.
- **API reference** —
  [`PayCross`](https://developers.pay-cross.com/reference/ios/paycross/documentation/paycross/) and
  [`PayCrossCore`](https://developers.pay-cross.com/reference/ios/paycrosscore/documentation/paycrosscore/).
- **[Changelog](https://developers.pay-cross.com/resources/changelogs/ios/)** —
  mirrored from [`CHANGELOG.md`](CHANGELOG.md).
- **[Support](https://developers.pay-cross.com/resources/support/)** — questions go to support@pay-cross.com.

Why the package is split in two, how to build it, and where it diverges from
Android on purpose are in [`docs/internal/DESIGN.md`](docs/internal/DESIGN.md).

## Contributing and security

`swift build` and `swift test` run on Linux without Xcode. Report a
vulnerability the way [`SECURITY.md`](SECURITY.md) describes, never as a public
issue.
