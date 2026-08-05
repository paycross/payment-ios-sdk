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
    /// A value this SDK version does not know. Treated as terminal.
    case unrecognized(String)

    /// Whether the user may retry payment within the same session.
    ///
    /// A whitelist, so anything unknown or terminal is not retryable.
    public var isRetryable: Bool {
        switch self {
        case .retry, .changeMethod: true
        case .restart, .contactSupport, .doNotRetry, .unrecognized: false
        }
    }

    /// Whether this SDK version understood the server's value.
    public var isRecognized: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    /// Parses a server recovery value.
    ///
    /// Absent values default to `.retry`; unrecognised values fail closed, matching
    /// `Recovery.fromString` in the Android SDK and the checkout page's policy.
    public init(apiValue: String?) {
        switch apiValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "": self = .retry
        case "retry": self = .retry
        case "change_method": self = .changeMethod
        case "restart": self = .restart
        case "contact_support", "contact_us": self = .contactSupport
        case "do_not_retry": self = .doNotRetry
        case let other?: self = .unrecognized(other)
        }
    }
}
