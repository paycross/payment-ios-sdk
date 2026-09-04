#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// A cancelled payment still leaves a transaction on the server.
///
/// The sheet resolves its own cancellation immediately — the shopper tapped
/// Cancel and the sheet has to go — so it never reads the id off the runner's
/// final outcome. Core pins that the runner carries the id; what is pinned here is
/// that the sheet has it at the moment the shopper walks away, which is the case
/// the bug is about: a cancel during a 3-D Secure challenge, where the transaction
/// is already sitting in `threeds_challenge_requested`.
@MainActor
final class CancelledTransactionIDTests: XCTestCase {

    private func makeModel(transport: any HTTPTransport) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                expiresAt: nil
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
            transport: transport
        )
    }

    private func typeACard(into model: PaymentSheetModel) {
        CardFormReducer.reduce(state: &model.form, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &model.form, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &model.form, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &model.form, event: .cvvChanged("123"))
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private actor ResultBox {
        private(set) var value: PaymentResult?
        func set(_ result: PaymentResult) { value = result }
    }

    /// Installs the continuation, runs `act`, then polls for the result.
    ///
    /// Polling rather than awaiting the task directly: a result that never arrives
    /// has to fail the test, not hang the suite.
    private func result(
        of model: PaymentSheetModel,
        after act: () async -> Void
    ) async -> PaymentResult? {
        let box = ResultBox()
        Task { await box.set(await model.awaitResult()) }
        try? await Task.sleep(for: .milliseconds(50))

        await act()

        let deadline = ContinuousClock().now + .seconds(5)
        while ContinuousClock().now < deadline {
            if let value = await box.value { return value }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await box.value
    }

    func testCancellingAPaymentInFlightNamesItsTransaction() async {
        let transport = StubTransport(replies: [
            .init(body: Data(#"{"success":true,"transaction_id":"txn_live"}"#.utf8)),
            .init(body: Data(#"{"transaction_id":"txn_live","status":"pending"}"#.utf8))
        ])
        let model = makeModel(transport: transport)
        typeACard(into: model)

        let outcome = await result(of: model) {
            model.pay()
            let gotID = await waitUntil { model.lastTransactionID != nil }
            XCTAssertTrue(gotID, "the flow never reported a transaction id")
            model.cancel()
        }

        XCTAssertEqual(
            outcome, .cancelled(transactionID: "txn_live"),
            "a shopper who walks away mid-payment leaves a transaction to reconcile"
        )
    }

    /// Cancelled before anything was submitted: there is no transaction, and
    /// inventing one would be worse than nil.
    func testCancellingBeforePayingNamesNothing() async {
        let model = makeModel(transport: StubTransport(status: 500))

        let outcome = await result(of: model) { model.cancel() }

        XCTAssertEqual(outcome, .cancelled(transactionID: nil))
    }
}
#endif
