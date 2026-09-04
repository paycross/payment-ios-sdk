#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// Pins the bound on a re-armed form.
///
/// The decision — what an expired session resolves to, and how long is left —
/// is Core's and is asserted on Linux in `SessionLifetimeTests`. What can only be
/// shown in a running process is that the sheet actually acts on it: a form
/// re-armed after a retryable decline has no other deadline, because the 480 s
/// poll deadline went with the poll it belonged to.
@MainActor
final class SessionDeadlineTests: XCTestCase {

    private func makeModel(expiresIn seconds: TimeInterval?) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                expiresAt: seconds.map { Int64(Date().timeIntervalSince1970 + $0) }
            ),
            configuration: Configuration(
                environment: .sandbox,
                testCardPrefill: nil,
                applePayMerchantIdentifier: nil
            ),
            walletAuthorizer: nil,
            deviceCanPay: { false },
            sessionData: nil,
            isPreparing: false,
            // Never the real one: a model holding URLSessionTransport would open a
            // socket to the live checkout API from a unit test.
            transport: StubTransport(status: 500)
        )
    }

    /// Installs the continuation, re-arms, then polls for a result until the
    /// timeout.
    ///
    /// Polling rather than racing the awaiting task in a task group: `awaitResult`
    /// never resumes when no result is coming, and a group waits for every child
    /// before it returns, so the "nothing should happen" case would hang the suite
    /// rather than fail. Same shape as `waitUntil` in `ApplePayPresentationTests`.
    private func resultOfReArming(
        _ model: PaymentSheetModel,
        within timeout: Duration
    ) async -> PaymentResult? {
        let box = ResultBox()
        Task { await box.set(await model.awaitResult()) }
        try? await Task.sleep(for: .milliseconds(50))
        model.reArm(with: "Payment failed. Please try again.")

        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if let result = await box.value { return result }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    private actor ResultBox {
        private(set) var value: PaymentResult?
        func set(_ result: PaymentResult) { value = result }
    }

    func testAReArmedFormEndsThePaymentOnceTheSessionExpires() async {
        let model = makeModel(expiresIn: 0.3)

        let result = await resultOfReArming(model, within: .seconds(5))

        XCTAssertEqual(
            result,
            .failed(transactionID: nil, recovery: .restart),
            "the sheet must not sit on a live Pay button after the session has expired"
        )
    }

    /// A session that never says when it ends is not one that has ended. Guessing
    /// a lifetime here would abandon payments the server would still have taken.
    func testAReArmedFormWithoutAnExpiryIsNotEnded() async {
        let model = makeModel(expiresIn: nil)

        let result = await resultOfReArming(model, within: .milliseconds(600))

        XCTAssertNil(result)
    }

    /// The message still reaches the form; the deadline is the only thing added.
    func testReArmingStillShowsTheDeclineAndReEnablesTheForm() {
        let model = makeModel(expiresIn: 600)

        model.reArm(with: "Payment failed. Please try again.")

        XCTAssertEqual(model.form.inlineError, "Payment failed. Please try again.")
        XCTAssertFalse(model.isLoading)
    }
}
#endif
