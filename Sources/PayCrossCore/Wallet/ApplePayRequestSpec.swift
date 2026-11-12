import Foundation

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

    // WHY: `Decimal`, not `Double`: a hundredth lost to binary floating point is a hundredth the shopper did not agree to.
    package var amountMajorUnits: Decimal { Amounts.majorUnits(amount) }

    package static func make(
        claims: SessionClaims,
        data: SessionData?,
        merchantIdentifier: String
    ) -> ApplePayRequestSpec {
        ApplePayRequestSpec(
            merchantIdentifier: merchantIdentifier,
            // WHY: Apple refuses a request with no country, and the session may name none; US is a default, not an inference about the shopper.
            countryCode: (data?.merchantCountry ?? "US").uppercased(),
            amount: claims.amount,
            summaryItemLabel: "Total",
            supportedNetworks: [.visa, .mastercard, .amex, .discover, .jcb],
            capabilities: [.threeDSecure, .credit, .debit]
        )
    }
}
