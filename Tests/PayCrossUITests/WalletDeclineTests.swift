#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// A wallet decline must not take the shopper's typed CVV with it.
///
/// Core owns the rule and asserts it on Linux in `CardFormTests`. What is asserted
/// here is that the sheet's wallet branch actually reaches for the wallet flavour
/// of the event — the defect was a card-path event used on three wallet paths, so
/// the wiring is the whole bug.
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
            // Never the real one: a model holding URLSessionTransport would open a
            // socket to the live checkout API from a unit test.
            transport: transport
        )
    }

    /// Fills the form the way a shopper would before changing their mind.
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

    /// The other wallet route, and the one the re-arm rework touches: the wallet
    /// payment reached the server and was declined retryably. The submission
    /// carried a payment token, so the card on the form was still never
    /// authorized and its CVV must survive.
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

    /// The shopper dismissing Apple Pay is not a decline and shows nothing, so the
    /// CVV is untouched for a different reason. Pinned so a future refactor cannot
    /// route it through a decline event.
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
