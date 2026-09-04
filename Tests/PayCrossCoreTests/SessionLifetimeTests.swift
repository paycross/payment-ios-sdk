import XCTest
@testable import PayCrossCore

/// How long a re-armed form may stay live.
final class SessionLifetimeTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func claims(expiresAt: Int64?) -> SessionClaims {
        SessionClaims(
            sessionID: "sess_1",
            merchantID: "merch_1",
            customerID: "cust_1",
            brandingID: nil,
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            expiresAt: expiresAt
        )
    }

    func testRemainingCountsDownToTheExpiry() {
        let remaining = SessionLifetime.remaining(
            claims: claims(expiresAt: Int64(noon.timeIntervalSince1970) + 90),
            now: noon
        )
        XCTAssertEqual(remaining, .seconds(90))
    }

    /// Zero rather than a negative duration: the caller sleeps on this, and a
    /// negative sleep is a programming error rather than "wake immediately".
    func testAnAlreadyExpiredSessionHasNoTimeLeft() {
        let remaining = SessionLifetime.remaining(
            claims: claims(expiresAt: Int64(noon.timeIntervalSince1970) - 5),
            now: noon
        )
        XCTAssertEqual(remaining, .zero)
    }

    /// Nil, not zero: a session that never says when it ends must not be treated
    /// as one that has already ended.
    func testASessionWithoutAnExpiryHasNoDeadline() {
        XCTAssertNil(SessionLifetime.remaining(claims: claims(expiresAt: nil), now: noon))
        XCTAssertNil(SessionLifetime.remaining(claims: nil, now: noon))
    }

    /// The same result the sheet already returns for a token that is expired
    /// before it opens, so one situation has one answer.
    func testAnExpiredSessionResolvesToRestart() {
        XCTAssertEqual(SessionLifetime.expired, .failed(transactionID: nil, recovery: .restart))
    }
}
