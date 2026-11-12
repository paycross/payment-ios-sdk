import XCTest
@testable import PayCrossCore

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

    func testAnAlreadyExpiredSessionHasNoTimeLeft() {
        let remaining = SessionLifetime.remaining(
            claims: claims(expiresAt: Int64(noon.timeIntervalSince1970) - 5),
            now: noon
        )
        XCTAssertEqual(remaining, .zero)
    }

    func testASessionWithoutAnExpiryHasNoDeadline() {
        XCTAssertNil(SessionLifetime.remaining(claims: claims(expiresAt: nil), now: noon))
        XCTAssertNil(SessionLifetime.remaining(claims: nil, now: noon))
    }

    func testAnExpiredSessionResolvesToRestart() {
        XCTAssertEqual(SessionLifetime.expired, .failed(transactionID: nil, recovery: .restart))
    }
}
