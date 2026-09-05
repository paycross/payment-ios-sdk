import Foundation

/// A suggested next step after a payment failure.
///
/// Deliberately not `RawRepresentable`. A `String` raw value would synthesise
/// `init?(rawValue:)`, which returns `nil` for unknown server values — a fail-open
/// parser sitting inches from the fail-closed one below. `unrecognized` keeps the
/// raw string for telemetry and keeps `isRetryable` a whitelist.
public enum Recovery: Sendable, Hashable {
    case retry
    case changeMethod
    case restart
    case contactSupport
    /// Terminal decline. Never offer a retry of this payment.
    case doNotRetry
    /// The outcome was never observed. Check the transaction's status before
    /// re-collecting.
    ///
    /// Never carried by a `.failed` result: see `PaymentResult.pending`. Parsing
    /// it off the wire is what this case is for — the server does send
    /// `verify_before_retry`, and a value the SDK cannot name would fall to
    /// `unrecognized` and read as "upgrade the SDK" instead of "nobody knows".
    /// The SDK turns it into `.pending(reason: .serverVerify)`, because
    /// reporting an unobserved outcome as a decline is what invited a merchant to
    /// charge a shopper twice. Not retryable, for that same reason.
    case verifyBeforeRetry
    /// A value this SDK version does not know. Treated as terminal.
    case unrecognized(String)

    /// Whether the user may retry payment within the same session.
    ///
    /// A whitelist, so anything unknown or terminal is not retryable.
    public var isRetryable: Bool {
        switch self {
        case .retry, .changeMethod: true
        case .restart, .contactSupport, .doNotRetry, .verifyBeforeRetry, .unrecognized: false
        }
    }

    /// Whether this SDK version understood the server's value.
    package var isRecognized: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    /// Parses a server recovery value.
    ///
    /// Absent values default to `.retry`; unrecognised values fail closed, matching
    /// `Recovery.fromString` in the Android SDK and the checkout page's policy.
    package init(apiValue: String?) {
        switch apiValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "": self = .retry
        case "retry": self = .retry
        case "change_method": self = .changeMethod
        case "restart": self = .restart
        case "contact_support", "contact_us": self = .contactSupport
        case "do_not_retry": self = .doNotRetry
        case "verify_before_retry": self = .verifyBeforeRetry
        case let other?: self = .unrecognized(other)
        }
    }
}
