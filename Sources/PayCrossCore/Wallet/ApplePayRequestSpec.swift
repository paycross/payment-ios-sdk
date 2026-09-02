import Foundation

/// A card scheme, named without naming PassKit.
///
/// `Sources/PayCrossCore` may not import PassKit -- CI greps for it -- and
/// spelling `PKPaymentNetwork`'s raw values here would put Apple's exact
/// capitalisation in a file that cannot see the symbols that define it. A typo
/// would produce an empty network list and a button that never appears, with
/// nothing to grep for. The adapter maps these cases to PassKit by symbol.
///
/// The list mirrors the Android SDK's `CARD_NETWORKS`, because the two clients
/// must offer the same schemes for the same merchant.
package enum ApplePayNetwork: String, Sendable, Hashable, CaseIterable {
    case visa
    case mastercard
    case amex
    case discover
    case jcb
}

/// A merchant capability, named without naming PassKit, for the same reason.
package enum ApplePayCapability: String, Sendable, Hashable, CaseIterable {
    case threeDSecure
    case credit
    case debit
}

/// Everything the PassKit adapter needs to build a payment request, decided
/// here so that all of it is provable on Linux.
package struct ApplePayRequestSpec: Sendable, Hashable {
    package let merchantIdentifier: String
    package let countryCode: String
    package let amount: Amount
    package let summaryItemLabel: String
    package let supportedNetworks: [ApplePayNetwork]
    package let capabilities: [ApplePayCapability]

    package var currencyCode: String { amount.currencyCode }

    /// What Apple's sheet quotes to the shopper, exact.
    ///
    /// `Decimal`, not `Double`: this is the number somebody reads before
    /// authorising, and a hundredth lost to binary floating point is a
    /// hundredth they did not agree to.
    package var amountMajorUnits: Decimal { Amounts.majorUnits(amount) }

    package static func make(
        claims: SessionClaims,
        data: SessionData?,
        merchantIdentifier: String
    ) -> ApplePayRequestSpec {
        ApplePayRequestSpec(
            merchantIdentifier: merchantIdentifier,
            // Apple refuses a request with no country and the session is
            // allowed not to name one. US is a default, not an inference
            // about the shopper.
            countryCode: data?.merchantCountry ?? "US",
            amount: claims.amount,
            // The merchant's own name is on Apple's sheet already, from the
            // Merchant ID Apple has on file; the SDK has no name of its own
            // to add and inventing one would contradict it.
            summaryItemLabel: "Total",
            supportedNetworks: [.visa, .mastercard, .amex, .discover, .jcb],
            // Three-D Secure is required by Apple for in-app payments; the
            // other two say the sheet may offer either kind of card.
            capabilities: [.threeDSecure, .credit, .debit]
        )
    }
}
