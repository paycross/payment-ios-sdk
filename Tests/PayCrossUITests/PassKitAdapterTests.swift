#if os(iOS)
import XCTest
import PassKit
@testable import PayCross
@testable import PayCrossCore

/// Exercises the one file that talks to PassKit.
///
/// Every other test in this target hands the payment sheet a fake
/// `WalletAuthorizing`, so before this file existed the adapter itself was
/// never executed: three separate one-line mutations of it -- dropping 3-D
/// Secure from the request, and never resuming the continuation -- left the
/// whole suite green.
///
/// A simulator cannot present Apple's sheet, so this splits the file into the
/// two halves that can be asserted without one. `makeRequest` is a pure
/// function of the spec and needs nothing. The continuation discipline is
/// driven through the delegate methods directly, against a controller that is
/// built but never presented.
@MainActor
final class PassKitAdapterTests: XCTestCase {

    // MARK: - The request Apple is handed

    private func spec(
        merchantIdentifier: String = "merchant.pay-cross.com",
        country: String = "GB",
        amount: Amount = Amount(minorUnits: 2599, currencyCode: "EUR")
    ) -> ApplePayRequestSpec {
        ApplePayRequestSpec.make(
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil, amount: amount, expiresAt: nil
            ),
            data: SessionData(merchantCountry: country),
            merchantIdentifier: merchantIdentifier
        )
    }

    func testTheRequestNamesTheMerchantTheCountryAndTheCurrency() {
        let request = PassKitWalletAuthorizer.makeRequest(spec())

        XCTAssertEqual(request.merchantIdentifier, "merchant.pay-cross.com")
        XCTAssertEqual(request.countryCode, "GB")
        XCTAssertEqual(request.currencyCode, "EUR")
    }

    /// Every scheme the spec names, mapped by symbol. The device check asks
    /// PassKit about this same list, so a network dropped here produces a
    /// button that appears for a card the sheet will then refuse.
    func testTheRequestCarriesEveryNetworkTheSpecNames() {
        let request = PassKitWalletAuthorizer.makeRequest(spec())

        XCTAssertEqual(
            Set(request.supportedNetworks),
            Set([PKPaymentNetwork.visa, .masterCard, .amex, .discover, .JCB])
        )
    }

    /// Apple requires 3-D Secure for in-app payments. Without this capability
    /// the sheet refuses to present for every merchant, and the only report is
    /// `present()` answering false.
    func testTheRequestKeepsTheThreeDSecureCapability() {
        let request = PassKitWalletAuthorizer.makeRequest(spec())

        XCTAssertTrue(
            request.merchantCapabilities.contains(.capability3DS),
            "Apple requires 3-D Secure for in-app payments; without it no sheet ever opens"
        )
        XCTAssertTrue(request.merchantCapabilities.contains(.capabilityCredit))
        XCTAssertTrue(request.merchantCapabilities.contains(.capabilityDebit))
    }

    /// The number the shopper reads before authorising, exact.
    func testTheSummaryItemQuotesTheAmountInMajorUnits() throws {
        let request = PassKitWalletAuthorizer.makeRequest(spec())
        let item = try XCTUnwrap(request.paymentSummaryItems.first)

        XCTAssertEqual(request.paymentSummaryItems.count, 1)
        XCTAssertEqual(item.label, "Total")
        XCTAssertEqual(item.type, .final)
        XCTAssertEqual(item.amount, NSDecimalNumber(string: "25.99"))
    }

    /// A zero-decimal currency is quoted whole. Dividing by 100 regardless
    /// would offer a ¥2599 payment as ¥25.99, and the shopper would authorise
    /// the wrong money.
    func testTheSummaryItemQuotesAZeroDecimalCurrencyWhole() throws {
        let request = PassKitWalletAuthorizer.makeRequest(
            spec(amount: Amount(minorUnits: 2599, currencyCode: "JPY"))
        )
        let item = try XCTUnwrap(request.paymentSummaryItems.first)

        XCTAssertEqual(item.amount, NSDecimalNumber(string: "2599"))
    }

    // MARK: - The continuation discipline

    private func stubController() -> PKPaymentAuthorizationController {
        PKPaymentAuthorizationController(paymentRequest: PassKitWalletAuthorizer.makeRequest(spec()))
    }

    /// The regression that hangs a payment forever.
    ///
    /// `didFinish` is the only thing that resumes, and it is reached after an
    /// authorisation, a cancel and a swipe-away alike. If it stops resuming,
    /// the sheet's task never returns, `isLoading` stays true, and the shopper
    /// is left with a locked form and Cancel as their only way out.
    func testTheDelegateResumesTheWaitingCaller() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }

        let installed = await waitUntil { authorizer.isAwaitingOutcome }
        XCTAssertTrue(installed, "the continuation was never installed")

        authorizer.paymentAuthorizationControllerDidFinish(stubController())

        let resumed = await waitUntil { box.value != nil }
        XCTAssertTrue(resumed, "didFinish must resume its caller, or the payment hangs forever")
        XCTAssertEqual(box.value, .cancelled, "a sheet that finished without authorising is a cancel")
        _ = await waiter.value
    }

    /// `resume` clears the continuation before resuming, so a second callback
    /// is a no-op rather than the double-resume that traps the process.
    func testASecondDidFinishIsHarmless() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }
        _ = await waitUntil { authorizer.isAwaitingOutcome }

        let controller = stubController()
        authorizer.paymentAuthorizationControllerDidFinish(controller)
        _ = await waitUntil { box.value != nil }
        authorizer.paymentAuthorizationControllerDidFinish(controller)

        XCTAssertFalse(authorizer.isAwaitingOutcome, "the continuation must not survive its resume")
        _ = await waiter.value
    }

    /// A second sheet on the same instance would overwrite the first
    /// continuation and leave its caller waiting forever, reported only as
    /// SWIFT TASK CONTINUATION MISUSE in the log.
    func testASecondAuthorizeIsRefusedWhileASheetIsOpen() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }
        _ = await waitUntil { authorizer.isAwaitingOutcome }

        let second = await authorizer.authorize(spec())

        XCTAssertEqual(second, .failed("An Apple Pay sheet is already open."))
        XCTAssertTrue(authorizer.isAwaitingOutcome, "the first caller must still be waiting")

        authorizer.paymentAuthorizationControllerDidFinish(stubController())
        _ = await waitUntil { box.value != nil }
        XCTAssertEqual(box.value, .cancelled, "the first caller must still get its own answer")
        _ = await waiter.value
    }

    /// The SDK's own worst error message.
    ///
    /// `present()` answers a bare false, and it answers it almost exclusively
    /// for a misconfigured request: an identifier missing from the app's Apple
    /// Pay entitlement, an unsupported country or currency. The shopper can
    /// still pay by card, so the sentence they read hardly matters; the
    /// merchant integrating the SDK has nothing else at all, and there is no
    /// log line.
    ///
    /// Asserted on the message builder rather than on a real failure, because
    /// the failure cannot be reached here: on this simulator `present()`
    /// neither succeeds nor returns, measured at a three-second timeout, so a
    /// test driving `authorize` skips rather than proving anything. That the
    /// failure branch returns *this* message is by inspection.
    func testThePresentationFailureMessageNamesWhatIsWrong() {
        let message = PassKitWalletAuthorizer.presentationFailureMessage(
            for: spec(merchantIdentifier: "merchant.example.invalid")
        )

        XCTAssertTrue(
            message.contains("merchant.example.invalid"),
            "the message must name the identifier that is wrong: \(message)"
        )
        XCTAssertTrue(
            message.contains("entitlement"),
            "the message must name where the merchant should look: \(message)"
        )
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return await condition()
    }
}

@MainActor
private final class OutcomeBox {
    var value: WalletAuthorizationOutcome?
}
#endif
