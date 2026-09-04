import Foundation

/// How long a session may still be used.
///
/// Pure, and takes its "now" as a parameter for the same reason `CardValidator`
/// does: the boundary cases have to be assertable without waiting on a clock.
package enum SessionLifetime {

    /// Time left before the session stops being usable.
    ///
    /// Zero once it has expired — the caller sleeps on this value, and a negative
    /// duration is a programming error rather than "wake immediately". Nil when
    /// the session carries no expiry at all, which is not the same as one that has
    /// already ended.
    package static func remaining(claims: SessionClaims?, now: Date = Date()) -> Duration? {
        guard let expiresAt = claims?.expiresAt else { return nil }
        let seconds = Double(expiresAt) - now.timeIntervalSince1970
        return seconds <= 0 ? .zero : .seconds(seconds)
    }

    /// What a payment resolves to once its session is no longer open.
    ///
    /// `.restart` rather than `.doNotRetry`: the card was never the problem and
    /// the merchant only has to mint a new session. It is also what the sheet
    /// already returns for a token that is expired before it opens, so the one
    /// situation has the one answer.
    package static let expired = PaymentResult.failed(transactionID: nil, recovery: .restart)
}
