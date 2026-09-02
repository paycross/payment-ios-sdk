import Foundation

/// Presents a wallet's own authorization UI and answers with a token.
///
/// Shaped after `ThreeDSPresenting`, and for the same reason: the only part of
/// this flow that needs a platform framework is the presentation, so it lives
/// behind a protocol and every decision around it stays testable on Linux. The
/// PassKit implementation is in `Sources/PayCross`, which is the only target
/// allowed to import it.
package protocol WalletAuthorizing: Sendable {
    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome
}

/// What came back from the wallet sheet.
///
/// A cancellation is not a failure and must not surface as one: the shopper
/// dismissed a sheet and is still looking at the card form, so there is
/// nothing to report and nothing to recover from.
package enum WalletAuthorizationOutcome: Sendable, Equatable {
    case authorized(JSONValue)
    case cancelled
    case failed(String)
}
