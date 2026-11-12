#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class CancelledTransactionIDTests: XCTestCase {

    private var originalUserAgentProvider: UserAgentProvider!

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

    private func result(
        of model: PaymentSheetModel,
        after act: () async -> Void
    ) async -> PaymentResult? {
        let box = ResultBox()
        let waiting = expectation(description: "the sheet is waiting for a result")
        let reported = expectation(description: "the sheet reported a result")

        Task { @MainActor in
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

    func testCancellingBeforePayingNamesNothing() async {
        let model = makeModel(transport: StubTransport(status: 500))

        let outcome = await result(of: model) { model.cancel() }

        XCTAssertEqual(outcome, .cancelled(transactionID: nil))
    }
}
#endif
