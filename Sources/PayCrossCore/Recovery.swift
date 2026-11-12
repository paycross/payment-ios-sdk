import Foundation

/// A suggested next step after a payment failure.
///
/// Not `RawRepresentable`: an unknown server value must not parse to a case.
public enum Recovery: Sendable, Hashable {
    case retry
    case changeMethod
    case restart
    case contactSupport
    /// Terminal decline. Never offer a retry of this payment.
    case doNotRetry
    /// The outcome is unknown. Check the transaction's status before collecting again.
    ///
    /// The server sends this value. The SDK reports it as `.pending`, never `.failed`.
    case verifyBeforeRetry
    /// A value this SDK version does not know. Treated as terminal.
    case unrecognized(String)

    /// Whether the user may retry payment within the same session.
    public var isRetryable: Bool {
        switch self {
        case .retry, .changeMethod: true
        case .restart, .contactSupport, .doNotRetry, .verifyBeforeRetry, .unrecognized: false
        }
    }

    package var isRecognized: Bool {
        if case .unrecognized = self { return false }
        return true
    }

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
