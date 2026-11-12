#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class WalletDeclineTests: XCTestCase {

    private func makeModel(
        authorizer: any WalletAuthorizing,
        transport: any HTTPTransport = StubTransport(status: 500)
    ) -> PaymentSheetModel {
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
                applePayMerchantIdentifier: "merchant.com.example"
            ),
            walletAuthorizer: authorizer,
            deviceCanPay: { true },
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
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func testAFailedWalletSheetKeepsTheTypedCVV() async {
        let model = makeModel(
            authorizer: StubAuthorizer(outcome: .failed("Apple Pay failed"))
        )
        typeACard(into: model)

        model.payWithApplePay()
        let shown = await waitUntil { model.form.inlineError != nil }

        XCTAssertTrue(shown, "the decline never reached the form")
        XCTAssertEqual(model.form.inlineError, "Apple Pay failed")
        XCTAssertEqual(
            model.form.cvvDigits, "123",
            "the wallet never saw this card, so there is nothing to discard"
        )
        XCTAssertFalse(model.isLoading)
    }

    func testAServerDeclinedWalletPaymentKeepsTheTypedCVV() async throws {
        let token = try JSONDecoder().decode(JSONValue.self, from: Data(Self.appleTokenJSON.utf8))
        let transport = StubTransport(replies: [
            .init(body: Data(#"{"success":true,"transaction_id":"txn_1"}"#.utf8)),
            .init(body: Data(#"{"transaction_id":"txn_1","status":"failed","recovery":"retry"}"#.utf8))
        ])
        let model = makeModel(
            authorizer: StubAuthorizer(outcome: .authorized(token)),
            transport: transport
        )
        typeACard(into: model)

        model.payWithApplePay()
        let shown = await waitUntil { model.form.inlineError != nil }

        XCTAssertTrue(shown, "the decline never reached the form")
        XCTAssertEqual(
            model.form.cvvDigits, "123",
            "a wallet submission carries a token, so the card on the form was never authorized"
        )
    }

    private static let appleTokenJSON = #"""
    {
      "paymentData": {
        "version": "EC_v1",
        "data": "4rMLBQ-encrypted-payload",
        "signature": "MEUCIQD-signature-bytes",
        "header": {
          "ephemeralPublicKey": "MFkwEw-ephemeral-key",
          "publicKeyHash": "LbsUwAT6w1JV9tFXocU813TCHks+LSuFF0R/eBkrWnQ=",
          "transactionId": "31323334353637383930"
        }
      },
      "paymentMethod": {
        "displayName": "Visa 1234",
        "network": "Visa",
        "type": "credit"
      },
      "transactionIdentifier": "31323334353637383930"
    }
    """#

    func testDismissingTheWalletSheetShowsNothingAndKeepsTheCVV() async {
        let model = makeModel(authorizer: StubAuthorizer(outcome: .cancelled))
        typeACard(into: model)

        model.payWithApplePay()
        _ = await waitUntil { !model.isLoading }

        XCTAssertNil(model.form.inlineError)
        XCTAssertEqual(model.form.cvvDigits, "123")
    }
}

private actor StubAuthorizer: WalletAuthorizing {
    private let outcome: WalletAuthorizationOutcome

    init(outcome: WalletAuthorizationOutcome) {
        self.outcome = outcome
    }

    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome {
        outcome
    }
}
#endif
