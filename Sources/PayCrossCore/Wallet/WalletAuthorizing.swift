import Foundation

package protocol WalletAuthorizing: Sendable {
    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome
}

package enum WalletAuthorizationOutcome: Sendable, Equatable {
    case authorized(JSONValue)
    // WHY: A cancelled sheet is not a failure; the shopper is still on the card form.
    case cancelled
    case failed(String)
}
