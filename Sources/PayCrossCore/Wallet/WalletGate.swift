import Foundation

/// Whether this session may offer a wallet, and whether this device and this
/// configuration can actually deliver one.
///
/// Two separate questions, kept separate because they fail for different
/// reasons and a merchant debugging a missing button needs to know which one
/// answered no.
package enum WalletGate {

    /// The session-level rule, strict-false.
    ///
    /// Offered unless the snapshot says `apple_pay: false` in so many words.
    /// An absent block and a null member are both "the server had no opinion",
    /// and every session minted before the backend shipped the block is the
    /// former. Account funding overrides everything: core rejects wallet
    /// payments on those sessions, so a button there buys a Face ID prompt and
    /// a rejection.
    package static func allowsApplePay(_ data: SessionData?) -> Bool {
        data?.wallets?.applePay != false && data?.accountFunding != true
    }

    /// The whole eligibility question: the session allows it, the integration
    /// configured an identifier, and the device has a card it can pay with.
    ///
    /// A blank identifier counts as unconfigured. Empty is what an unset build
    /// constant produces and whitespace is what a hand-cleared text field
    /// leaves behind, and the failure they cause downstream is the worst one
    /// available -- the submit body omits `merchant_identifier` or carries one
    /// the signed session claim cannot match, the edge reads the payment as a
    /// web token, the vault derives the wrong key, and the shopper sees a
    /// generic decline.
    package static func offersApplePay(
        data: SessionData?,
        merchantIdentifier: String?,
        deviceCanPay: Bool
    ) -> Bool {
        guard let merchantIdentifier,
              !merchantIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        return allowsApplePay(data) && deviceCanPay
    }
}
