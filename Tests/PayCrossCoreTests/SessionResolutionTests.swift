import XCTest
@testable import PayCrossCore

/// Guards the second-authorization path. Before this existed, a session the
/// shopper had already paid rendered the card form again, and the retry minted a
/// fresh idempotency key so the backend had no way to relate the two.
final class SessionResolutionTests: XCTestCase {

    private var claims: SessionClaims {
        SessionClaims(
            sessionID: "sess_1", merchantID: "m", customerID: "c", brandingID: nil,
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
        )
    }

    private func session(
        status: String?,
        latest: String? = nil,
        data: SessionData? = nil
    ) -> SessionResponse {
        SessionResponse(
            sessionID: "sess_1", status: status,
            latestTransactionID: latest, data: data
        )
    }

    // MARK: - The money bug

    func testCompletedSessionWithATransactionResumesRatherThanShowingAForm() {
        let resolution = SessionResolver.resolve(
            session(status: "completed", latest: "txn_1"), claims: claims
        )
        XCTAssertEqual(resolution, .resume(transactionID: "txn_1"))
    }

    /// Paid, but the server named no transaction. Android reports success with an
    /// empty id rather than charging again.
    func testCompletedSessionWithNoTransactionFinishesSuccessfully() {
        let resolution = SessionResolver.resolve(session(status: "completed"), claims: claims)
        XCTAssertEqual(resolution, .finish(.succeeded(
            transactionID: "", status: "success",
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            savedCardToken: nil
        )))
    }

    func testCompletedSessionNeverShowsTheForm() {
        for latest in [nil, "txn_1"] {
            let resolution = SessionResolver.resolve(
                session(status: "completed", latest: latest), claims: claims
            )
            if case .showForm = resolution {
                XCTFail("a paid session must never invite a second payment")
            }
        }
    }

    // MARK: - Expiry

    /// Failing here means the shopper is told before typing a card, not after.
    func testExpiredSessionFinishesWithRestart() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "expired"), claims: claims),
            .finish(.failed(transactionID: nil, recovery: .restart))
        )
    }

    func testExpiredSessionCarriesTheTransactionWhenThereIsOne() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "expired", latest: "txn_9"), claims: claims),
            .finish(.failed(transactionID: "txn_9", recovery: .restart))
        )
    }

    // MARK: - Open sessions

    func testOpenSessionWithNothingInFlightShowsTheForm() {
        let data = SessionData(locale: "en-GB")
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "open", data: data), claims: claims),
            .showForm(data)
        )
    }

    /// Backgrounded mid-3DS and re-presented: resume the transaction instead of
    /// creating a second one.
    func testOpenSessionWithALatestTransactionResumes() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "open", latest: "txn_5"), claims: claims),
            .resume(transactionID: "txn_5")
        )
    }

    func testLocalTransactionTakesPrecedenceOverTheServers() {
        XCTAssertEqual(
            SessionResolver.resolve(
                session(status: "open", latest: "txn_server"),
                claims: claims,
                localTransactionID: "txn_local"
            ),
            .resume(transactionID: "txn_local")
        )
    }

    /// An empty string is not a transaction; resuming "" would poll a nonexistent
    /// id until the deadline.
    func testBlankLatestTransactionIsTreatedAsAbsent() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "open", latest: ""), claims: claims),
            .showForm(nil)
        )
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "completed", latest: "  "), claims: claims),
            .finish(.succeeded(
                transactionID: "", status: "success",
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                savedCardToken: nil
            ))
        )
    }

    // MARK: - Degraded cases

    /// A failed fetch must still let the shopper pay; Android falls through to
    /// the form too.
    func testFailedFetchShowsTheForm() {
        XCTAssertEqual(SessionResolver.resolve(nil, claims: claims), .showForm(nil))
    }

    func testUnknownStatusIsTreatedAsOpen() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: "something_new"), claims: claims),
            .showForm(nil)
        )
        XCTAssertEqual(
            SessionResolver.resolve(
                session(status: "something_new", latest: "txn_1"), claims: claims
            ),
            .resume(transactionID: "txn_1")
        )
    }

    func testMissingStatusIsTreatedAsOpen() {
        XCTAssertEqual(
            SessionResolver.resolve(session(status: nil), claims: claims),
            .showForm(nil)
        )
    }
}
