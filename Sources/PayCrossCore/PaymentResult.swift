import Foundation

/// A monetary amount in minor units, with its currency.
public struct Amount: Sendable, Hashable {
    public let minorUnits: Int64
    /// The ISO 4217 code, for example "EUR". May be empty.
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }
}

/// The outcome of a payment flow. A decline is `.failed`, not a thrown error.
public enum PaymentResult: Sendable, Hashable {
    /// The payment completed. `savedCardToken` is nil when the payment stored no card. It is not a card number and works only on this merchant's account.
    case succeeded(
        transactionID: String,
        status: String,
        amount: Amount,
        savedCardToken: String?
    )
    /// The payment failed. `transactionID` may be nil for early failures.
    case failed(transactionID: String?, recovery: Recovery)
    /// The outcome is unknown, and the payment may have succeeded. Reconcile against `transactionID` before charging again.
    case pending(transactionID: String?, reason: PendingReason)
    /// The shopper dismissed the payment sheet. A payment cancelled mid-authorization may still complete.
    case cancelled(transactionID: String?)
}

/// Why a payment's outcome is unknown. The raw values are shared with the Android SDK and the Flutter plugin.
public enum PendingReason: String, Sendable, Hashable, CaseIterable {
    /// The status poll ran out of time before a verdict.
    case pollTimeout = "poll_timeout"
    /// A result was produced but never reached the caller. Only the Flutter plugin produces this.
    case resultLost = "result_lost"
    /// The server could not give a verdict on a failed transaction.
    case serverVerify = "server_verify"
}
