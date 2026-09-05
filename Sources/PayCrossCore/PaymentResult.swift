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
    ///
    /// `savedCardToken` is the token for a card this payment stored, and is nil
    /// whenever the payment stored none — the shopper left the save toggle off,
    /// paid with a card already on file, or the session was resolved as complete
    /// without a status of its own to read one from. It is the merchant's handle
    /// on the stored card for a later payment; it is not a card number and is
    /// useless anywhere but this merchant's own account.
    case succeeded(
        transactionID: String,
        status: String,
        amount: Amount,
        savedCardToken: String?
    )
    /// The payment failed. `transactionID` may be nil for early failures.
    case failed(transactionID: String?, recovery: Recovery)
    /// The outcome is not known. The payment MAY have succeeded.
    ///
    /// Not a decline and not a success: the SDK never saw a verdict, and a payment
    /// that completed and shifted liability is indistinguishable from one that
    /// never happened. Reconcile server-side against `transactionID` before
    /// charging again — re-collecting on this is the one path that can charge a
    /// shopper twice. `transactionID` is nil only where there was no transaction
    /// to name; the SDK's own poll deadline always carries one.
    case pending(transactionID: String?, reason: PendingReason)
    /// The user dismissed the payment sheet.
    ///
    /// `transactionID` is the last transaction this session created, or nil when
    /// the sheet was dismissed before one existed. The server keeps its own record
    /// and a payment cancelled mid-authorization may still complete, so this is
    /// what lets the merchant reconcile the one the shopper walked away from.
    case cancelled(transactionID: String?)
}

/// Why a payment's outcome is unknown.
///
/// The raw values are the wire vocabulary, agreed verbatim with the Android SDK
/// and the Flutter plugin, so the same unresolved payment reads identically
/// whichever platform reported it. Renaming one is a wire break, not a rename.
///
/// The `String` raw value here is an output — what this SDK hands the bridges —
/// and nothing on iOS ever parses one back off the wire, so the synthesised
/// `init?(rawValue:)` is not the fail-open parser `Recovery` refuses to have. A
/// reason the SDK does not know cannot arrive, because none arrives at all.
public enum PendingReason: String, Sendable, Hashable, CaseIterable {
    /// The status poll ran out of time without ever seeing a verdict. A full
    /// network loss looks exactly like a blip the loop was right to ignore.
    case pollTimeout = "poll_timeout"
    /// A result was produced but never reached the caller. The native SDK does
    /// not produce this: it exists for the Flutter plugin, whose result crosses a
    /// platform channel that can drop it, and it is in the shared vocabulary so
    /// merchant code handling pending outcomes handles it on every platform.
    case resultLost = "result_lost"
    /// The server answered `verify_before_retry` on a failed transaction, which
    /// says it has no verdict to give either.
    case serverVerify = "server_verify"
}
