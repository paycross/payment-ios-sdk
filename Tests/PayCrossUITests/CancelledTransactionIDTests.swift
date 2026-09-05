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

    private var originalUserAgentProvider: UserAgentProvider!

    /// WebKit is never touched. `pay()` reads the user agent out of a throwaway
    /// `WKWebView` on its way to the submit body, and building one waits on
    /// WebKit's helper processes: on a loaded machine that holds the main actor
    /// long enough that nothing else on it — including a test waiting for the
    /// flow — makes any progress. `UserAgentWarmUpTests` covers that read.
    override func setUp() async throws {
        try await super.setUp()
        originalUserAgentProvider = DeviceInfo.userAgentProvider
        DeviceInfo.userAgentProvider = { "Mozilla/5.0 (iPhone) StubAgent/1.0" }
    }

    override func tearDown() async throws {
        DeviceInfo.userAgentProvider = originalUserAgentProvider
        try await super.tearDown()
    }

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

    private actor ResultBox {
        private(set) var value: PaymentResult?
        func set(_ result: PaymentResult) { value = result }
    }

    /// Installs the continuation, runs `act`, then reports what the sheet resolved.
    ///
    /// The install is waited on rather than slept over: `finish` drops a result
    /// nothing is waiting for, so an `act` that gets there first loses the outcome
    /// altogether. The timeouts bound the test rather than drive it — a result
    /// that never arrives has to fail the test, not hang the suite.
    private func result(
        of model: PaymentSheetModel,
        after act: () async -> Void
    ) async -> PaymentResult? {
        let box = ResultBox()
        let waiting = expectation(description: "the sheet is waiting for a result")
        let reported = expectation(description: "the sheet reported a result")

        Task { @MainActor in
            // Nothing suspends between this and the continuation going in, so the
            // wait below cannot return before the sheet is ready to be finished.
            waiting.fulfill()
            await box.set(await model.awaitResult())
            reported.fulfill()
        }
        await fulfillment(of: [waiting], timeout: 5)

        await act()

        await fulfillment(of: [reported], timeout: 5)
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
            // The runner hands the id to the sheet before it starts polling, so
            // the status request arriving is proof the sheet already has it.
            await transport.hasBeenAsked(for: 2)
            XCTAssertNotNil(
                model.lastTransactionID, "the flow never reported a transaction id"
            )
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
