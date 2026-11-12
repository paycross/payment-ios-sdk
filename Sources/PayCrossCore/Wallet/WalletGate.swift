import Foundation

package enum WalletGate {
    // WHY: Only an explicit `apple_pay: false` disables the wallet; absent means no opinion.
    // WHY: An account-funding session can take a wallet payment; its transfer fields come first.
    package static func allowsApplePay(_ data: SessionData?) -> Bool {
        data?.wallets?.applePay != false
    }

    // WHY: A blank merchant identifier counts as unconfigured.
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
