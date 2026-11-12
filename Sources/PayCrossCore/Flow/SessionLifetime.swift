import Foundation

package enum SessionLifetime {

    /// The time left before the session expires, zero once it has expired, or nil when it has no expiry.
    package static func remaining(claims: SessionClaims?, now: Date = Date()) -> Duration? {
        guard let expiresAt = claims?.expiresAt else { return nil }
        let seconds = Double(expiresAt) - now.timeIntervalSince1970
        return seconds <= 0 ? .zero : .seconds(seconds)
    }

    /// The result for a payment whose session has ended. Recovery is `.restart`, since a new session fixes it.
    package static let expired = PaymentResult.failed(transactionID: nil, recovery: .restart)
}
