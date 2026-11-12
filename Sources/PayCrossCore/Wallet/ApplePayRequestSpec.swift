import Foundation

// PayCrossCore may not import PassKit (ci.yml greps for it). The list mirrors Android's CARD_NETWORKS, so both clients offer the same schemes.
package enum ApplePayNetwork: String, Sendable, Hashable, CaseIterable {
    case visa
    case mastercard
    case amex
    case discover
    case jcb
}

package enum ApplePayCapability: String, Sendable, Hashable, CaseIterable {
    case threeDSecure
    case credit
    case debit
}

package struct ApplePayRequestSpec: Sendable, Hashable {
    package let merchantIdentifier: String
    package let countryCode: String
    package let amount: Amount
    package let summaryItemLabel: String
    package let supportedNetworks: [ApplePayNetwork]
    package let capabilities: [ApplePayCapability]

    package var currencyCode: String { amount.currencyCode.uppercased() }

    // `Decimal`, not `Double`: a hundredth lost to binary floating point is a hundredth the shopper did not agree to.
    package var amountMajorUnits: Decimal { Amounts.majorUnits(amount) }

    package static func make(
        claims: SessionClaims,
        data: SessionData?,
        merchantIdentifier: String
    ) -> ApplePayRequestSpec {
        ApplePayRequestSpec(
            merchantIdentifier: merchantIdentifier,
            // Apple refuses a request with no country, and the session may name none; US is a default, not an inference about the shopper.
            countryCode: (data?.merchantCountry ?? "US").uppercased(),
            amount: claims.amount,
            // The sheet shows the merchant's name from its Apple Merchant ID; the SDK adds none, so it must not invent one.
            summaryItemLabel: "Total",
            supportedNetworks: [.visa, .mastercard, .amex, .discover, .jcb],
            // Apple requires Three-D Secure for in-app payments; credit and debit say the sheet may offer either kind of card.
            capabilities: [.threeDSecure, .credit, .debit]
        )
    }
}
