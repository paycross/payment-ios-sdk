import XCTest
@testable import PayCrossCore

final class PaymentFlowReducerTests: XCTestCase {

    private func claims(
        amount: Int64 = 1000,
        currency: String = "EUR",
        expiresAt: Int64? = nil
    ) -> SessionClaims {
        SessionClaims(
            sessionID: "sess_1",
            merchantID: "merch_1",
            customerID: "cust_1",
            brandingID: nil,
            amount: Amount(minorUnits: amount, currencyCode: currency),
            expiresAt: expiresAt
        )
    }

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Success

    func testSuccessFinishesWithTransactionDetails() {
        var state = PaymentFlowState(claims: claims())
        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "success", amount: 2500, currency: "USD")
            )
        )

        XCTAssertEqual(
            state.result,
            .succeeded(
                transactionID: "txn_1",
                status: "success",
                amount: Amount(minorUnits: 2500, currencyCode: "USD")
            )
        )
        XCTAssertTrue(effects.contains(.stopPolling))
        XCTAssertFalse(state.isPolling)
    }

    func testAuthorizedIsAlsoTerminalSuccess() {
        var state = PaymentFlowState(claims: claims())
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(StatusResponse(transactionID: "txn_1", status: "authorized"))
        )
        guard case .succeeded(_, let status, _) = state.result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(status, "authorized")
    }

    /// Android coalesces amount and currency independently; a status carrying only
    /// one of them must still pick the other up from the session claims.
    func testAmountAndCurrencyFallBackIndependently() {
        var state = PaymentFlowState(claims: claims(amount: 1000, currency: "EUR"))
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "t", status: "success", amount: 4200, currency: nil)
            )
        )
        XCTAssertEqual(state.result, .succeeded(
            transactionID: "t",
            status: "success",
            amount: Amount(minorUnits: 4200, currencyCode: "EUR")
        ))
    }

    func testMissingAmountAndNoClaimsDefaultsToZeroAndEmptyCurrency() {
        var state = PaymentFlowState(claims: nil)
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(StatusResponse(transactionID: "t", status: "success"))
        )
        XCTAssertEqual(state.result, .succeeded(
            transactionID: "t",
            status: "success",
            amount: Amount(minorUnits: 0, currencyCode: "")
        ))
    }

    // MARK: - Failure

    /// The defect the review caught. Android's handleStatus returns `true` for a
    /// retryable decline, which ends the poll job, even though it emits no result.
    func testRetryableDeclineStopsPollingWithoutFinishing() {
        var state = PaymentFlowState(claims: claims())
        state.transactionID = "txn_1"
        state.handledThreeDSKeys.insert("stale")

        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "retry")
            )
        )

        XCTAssertTrue(effects.contains(.stopPolling), "a dead transaction must not keep being polled")
        XCTAssertNil(state.result, "a retryable decline re-arms the form, it does not end the sheet")
        XCTAssertNil(state.transactionID)
        XCTAssertTrue(state.handledThreeDSKeys.isEmpty, "re-arming clears handled 3DS actions")
        XCTAssertEqual(state.inlineError, "Payment failed. Please try again.")
    }

    /// A re-armed form is only worth showing while the session can still take a
    /// payment. Nothing else bounds it — the 480 s poll deadline goes with the
    /// poll — so the sheet would otherwise sit on a live Pay button long after the
    /// session expired, and the shopper's next tap could only fail.
    func testRetryableDeclineOnAnExpiredSessionIsTerminal() {
        var state = PaymentFlowState(
            claims: claims(expiresAt: Int64(noon.timeIntervalSince1970) - 1)
        )
        state.transactionID = "txn_1"

        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "retry")
            ),
            now: noon
        )

        XCTAssertEqual(state.result, .failed(transactionID: nil, recovery: .restart))
        XCTAssertTrue(effects.contains(.finish(.failed(transactionID: nil, recovery: .restart))))
        XCTAssertNil(state.inlineError, "a dead session must not offer the form again")
    }

    func testRetryableDeclineStillReArmsWhileTheSessionIsOpen() {
        var state = PaymentFlowState(
            claims: claims(expiresAt: Int64(noon.timeIntervalSince1970) + 60)
        )

        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "retry")
            ),
            now: noon
        )

        XCTAssertNil(state.result)
        XCTAssertEqual(state.inlineError, "Payment failed. Please try again.")
    }

    /// A session with no `exp` claim at all is not treated as expired.
    func testRetryableDeclineReArmsWhenTheSessionHasNoExpiry() {
        var state = PaymentFlowState(claims: claims(expiresAt: nil))

        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "retry")
            ),
            now: noon
        )

        XCTAssertNil(state.result)
        XCTAssertEqual(state.inlineError, "Payment failed. Please try again.")
    }

    func testNonRetryableDeclineFinishes() {
        var state = PaymentFlowState(claims: claims())
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "do_not_retry")
            )
        )
        XCTAssertEqual(state.result, .failed(transactionID: "txn_1", recovery: .doNotRetry))
    }

    /// An unknown recovery value must end the payment, not re-arm the form.
    func testUnknownRecoveryFailsClosedAndFinishes() {
        var state = PaymentFlowState(claims: claims())
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "txn_1", status: "failed", recovery: "brand_new_value")
            )
        )
        XCTAssertEqual(
            state.result,
            .failed(transactionID: "txn_1", recovery: .unrecognized("brand_new_value"))
        )
    }

    // MARK: - 3DS

    func testFingerprintAndChallengeArePresented() {
        var state = PaymentFlowState(claims: claims())
        let action = ThreeDSAction(url: "https://acs.example/fp", method: "POST", data: ["a": "1"])

        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "t", status: "threeds_fingerprint", action: action)
            )
        )
        XCTAssertEqual(effects, [.present3DS(ThreeDSStep(action: action, isChallenge: false))])

        let challenge = ThreeDSAction(url: "https://acs.example/ch", method: "GET", data: nil)
        let challengeEffects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "t", status: "threeds_challenge", action: challenge)
            )
        )
        XCTAssertEqual(challengeEffects, [.present3DS(ThreeDSStep(action: challenge, isChallenge: true))])
    }

    func testSameActionIsNotPresentedTwice() {
        var state = PaymentFlowState(claims: claims())
        let action = ThreeDSAction(url: "https://acs.example/ch", method: "POST", data: ["x": "1"])
        let status = StatusResponse(transactionID: "t", status: "threeds_challenge", action: action)

        let first = PaymentFlowReducer.reduce(state: &state, event: .statusReceived(status))
        let second = PaymentFlowReducer.reduce(state: &state, event: .statusReceived(status))

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty, "polling re-delivers the same action; it must not re-present")
    }

    /// The porting bug the review caught: Kotlin's LinkedHashMap.toString() is
    /// insertion-ordered, Swift's Dictionary is not. Without sorting, the same
    /// action yields different keys and the challenge re-shows mid-payment.
    func testDedupeKeyIsStableRegardlessOfDictionaryOrder() {
        let a = ThreeDSAction(url: "u", method: "POST", data: ["z": "1", "a": "2", "m": "3"])
        let b = ThreeDSAction(url: "u", method: "POST", data: ["a": "2", "m": "3", "z": "1"])

        XCTAssertEqual(
            PaymentFlowReducer.dedupeKey(status: "threeds_challenge", action: a),
            PaymentFlowReducer.dedupeKey(status: "threeds_challenge", action: b)
        )
    }

    func testDedupeKeyDistinguishesDifferentActions() {
        let a = ThreeDSAction(url: "u1", method: "POST", data: ["a": "1"])
        let b = ThreeDSAction(url: "u2", method: "POST", data: ["a": "1"])
        XCTAssertNotEqual(
            PaymentFlowReducer.dedupeKey(status: "threeds_challenge", action: a),
            PaymentFlowReducer.dedupeKey(status: "threeds_challenge", action: b)
        )
    }

    func testStatusWithoutActionIsIgnored() {
        var state = PaymentFlowState(claims: claims())
        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "t", status: "threeds_challenge", action: nil)
            )
        )
        XCTAssertTrue(effects.isEmpty)
        XCTAssertNil(state.pendingThreeDS)
    }

    func testThreeDSCompletionClearsThePendingStepButKeepsTheDedupeKey() {
        var state = PaymentFlowState(claims: claims())
        let action = ThreeDSAction(url: "u", method: "GET", data: nil)
        _ = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(
                StatusResponse(transactionID: "t", status: "threeds_challenge", action: action)
            )
        )
        let effects = PaymentFlowReducer.reduce(state: &state, event: .threeDSCompleted)

        XCTAssertNil(state.pendingThreeDS)
        XCTAssertEqual(state.handledThreeDSKeys.count, 1, "polling must not re-show the completed step")
        // Emitting the dismissal is what actually removes the web view. Returning
        // [] here left an answered challenge full-screen over the form until the
        // next poll returned terminal, and left a completed fingerprint's web
        // view in the hierarchy for the life of the sheet.
        XCTAssertEqual(effects, [.dismiss3DS])
    }

    // MARK: - Unknown statuses and deadline

    func testUnknownStatusKeepsPolling() {
        var state = PaymentFlowState(claims: claims())
        let effects = PaymentFlowReducer.reduce(
            state: &state,
            event: .statusReceived(StatusResponse(transactionID: "t", status: "pending"))
        )
        XCTAssertTrue(effects.isEmpty)
        XCTAssertNil(state.result)
    }

    func testDeadlineFailsWithRetry() {
        var state = PaymentFlowState(claims: claims())
        state.transactionID = "txn_1"
        let effects = PaymentFlowReducer.reduce(state: &state, event: .pollDeadlineReached)

        XCTAssertEqual(state.result, .failed(transactionID: "txn_1", recovery: .retry))
        XCTAssertTrue(effects.contains(.stopPolling))
    }

    func testLimitsMatchTheKotlin() {
        XCTAssertEqual(FlowLimits.maxSubmitAttempts, 5)
        XCTAssertEqual(FlowLimits.pollInterval, .milliseconds(2000))
        XCTAssertEqual(FlowLimits.pollDeadline, .seconds(480))
    }
}
