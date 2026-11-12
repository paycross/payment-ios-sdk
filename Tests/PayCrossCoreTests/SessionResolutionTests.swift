import XCTest
@testable import PayCrossCore

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
