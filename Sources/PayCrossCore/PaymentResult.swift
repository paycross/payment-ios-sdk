import Foundation

/// A monetary amount in minor units, with its currency.
///
/// `minorUnits` is `Int64` to match the Kotlin `Long` and the wire type exactly,
/// rather than relying on `Int` happening to be 64-bit.
public struct Amount: Sendable, Hashable {
    public let minorUnits: Int64
    /// ISO 4217, e.g. "EUR". May be empty when the server sent neither an amount
    /// nor session claims to fall back on.
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }
}

/// The outcome of a payment flow.
///
/// Nothing here is thrown. A decline is `.failed`, not a Swift `Error`, so the
/// happy path does not need a `catch` and the compiler still checks that the
/// recovery branch was handled.
public enum PaymentResult: Sendable, Hashable {
    /// The payment completed.
    ///
    /// `transactionID` is empty in the edge case where the session was already
    /// complete and the server returned no transaction reference.
    case succeeded(transactionID: String, status: String, amount: Amount)
    /// The payment failed. `transactionID` may be nil for early failures.
    case failed(transactionID: String?, recovery: Recovery)
    /// The user dismissed the payment sheet.
    case cancelled
}
