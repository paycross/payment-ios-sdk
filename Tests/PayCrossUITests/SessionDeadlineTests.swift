#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

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
            transport: StubTransport(status: 500)
        )
    }

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

    func testAReArmedFormWithoutAnExpiryIsNotEnded() async {
        let model = makeModel(expiresIn: nil)

        let result = await resultOfReArming(model, within: .milliseconds(600))

        XCTAssertNil(result)
    }

    func testReArmingStillShowsTheDeclineAndReEnablesTheForm() {
        let model = makeModel(expiresIn: 600)

        model.reArm(with: "Payment failed. Please try again.")

        XCTAssertEqual(model.form.inlineError, "Payment failed. Please try again.")
        XCTAssertFalse(model.isLoading)
    }
}
#endif
