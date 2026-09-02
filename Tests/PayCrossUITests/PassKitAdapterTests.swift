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
        await settle(waiter, resumed: resumed)
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
        let resumed = await waitUntil { box.value != nil }
        authorizer.paymentAuthorizationControllerDidFinish(controller)

        XCTAssertFalse(authorizer.isAwaitingOutcome, "the continuation must not survive its resume")
        await settle(waiter, resumed: resumed)
    }

    /// A second sheet on the same instance would overwrite the first
    /// continuation and leave its caller waiting forever, reported only as
    /// SWIFT TASK CONTINUATION MISUSE in the log.
    func testASecondAuthorizeIsRefusedWhileASheetIsOpen() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }
        _ = await waitUntil { authorizer.isAwaitingOutcome }

        // Bounded, because the regression this catches is precisely a second
        // authorize that goes on to `present()` -- which on a simulator with no
        // entitlement neither succeeds nor returns. Awaiting it directly would
        // hang the run instead of failing the test.
        let secondBox = OutcomeBox()
        let attempt = Task { @MainActor in secondBox.value = await authorizer.authorize(spec()) }
        let answered = await waitUntil { secondBox.value != nil }

        XCTAssertTrue(answered, "a second sheet must be refused at once, not opened")
        XCTAssertEqual(secondBox.value, .failed("An Apple Pay sheet is already open."))
        XCTAssertTrue(authorizer.isAwaitingOutcome, "the first caller must still be waiting")
        await settle(attempt, resumed: answered)

        authorizer.paymentAuthorizationControllerDidFinish(stubController())
        let resumed = await waitUntil { box.value != nil }
        XCTAssertEqual(box.value, .cancelled, "the first caller must still get its own answer")
        await settle(waiter, resumed: resumed)
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

    // MARK: - The token, as PassKit hands it over

    /// The last function in this file that a device was the only thing
    /// executing.
    ///
    /// Deleting the `paymentMethod` key from what `tokenJSON` emits left all
    /// fifty tests green, because the authorised-path test walks a fixture the
    /// fake authorizer supplies rather than anything this function produced.
    /// The edge lifts three fields out of that object: `network` becomes the
    /// card brand the vault seals into the wallet credential and the provider
    /// forwards to the gateway, `displayName` becomes the masked digits, and
    /// `type` becomes the funding type the back office shows. Losing it
    /// degrades all three at once with no error anywhere.
    func testTheTokenCarriesEveryFieldTheEdgeReads() throws {
        let json = try XCTUnwrap(
            PassKitWalletAuthorizer.tokenJSON(StubPaymentToken()),
            "a well-formed token must convert"
        )
        let object = try encoded(json)

        let paymentData = try XCTUnwrap(object["paymentData"] as? [String: Any], "paymentData is the field the edge looks for first")
        let header = try XCTUnwrap(paymentData["header"] as? [String: Any])
        XCTAssertEqual(paymentData["version"] as? String, "EC_v1")
        XCTAssertEqual(paymentData["signature"] as? String, "MEUCIQD-signature-bytes")
        XCTAssertEqual(paymentData["data"] as? String, "4rMLBQ-encrypted-payload")
        XCTAssertEqual(header["publicKeyHash"] as? String, "LbsUwAT6w1JV9tFXocU813TCHks+LSuFF0R/eBkrWnQ=")
        XCTAssertEqual(header["ephemeralPublicKey"] as? String, "MFkwEw-ephemeral-key")
        XCTAssertEqual(header["transactionId"] as? String, "31323334353637383930")

        let method = try XCTUnwrap(object["paymentMethod"] as? [String: Any], "the edge lifts the brand, the masked digits and the funding type out of paymentMethod")
        XCTAssertEqual(method["network"] as? String, PKPaymentNetwork.visa.rawValue)
        XCTAssertEqual(method["displayName"] as? String, "Visa 1234")
        XCTAssertEqual(method["type"] as? String, "credit")

        XCTAssertEqual(object["transactionIdentifier"] as? String, "31323334353637383930")
        XCTAssertEqual(
            Set(object.keys), ["paymentData", "paymentMethod", "transactionIdentifier"],
            "the body must be exactly what the web checkout posts"
        )
    }

    /// `paymentData` is nested at the top level and not re-modelled on the way
    /// through, so a field Apple adds tomorrow survives. Asserted by putting an
    /// unknown key in the fixture and reading it back out.
    func testAnUnknownFieldInsideTheTokenSurvives() throws {
        let json = try XCTUnwrap(PassKitWalletAuthorizer.tokenJSON(StubPaymentToken()))
        let paymentData = try XCTUnwrap(try encoded(json)["paymentData"] as? [String: Any])

        XCTAssertEqual(
            paymentData["somethingAppleAddedLater"] as? String, "kept",
            "the token is carried through, not modelled; a dropped unknown field is a decryption failure with no field to point at"
        )
    }

    /// The funding type the back office shows, mapped by symbol.
    func testTheFundingTypeIsNamedRatherThanNumbered() throws {
        for (type, expected) in [
            (PKPaymentMethodType.credit, "credit"),
            (.debit, "debit"),
            (.prepaid, "prepaid"),
            (.store, "store")
        ] {
            let token = StubPaymentToken(method: StubPaymentMethod(type: type))
            let json = try XCTUnwrap(PassKitWalletAuthorizer.tokenJSON(token))
            let method = try XCTUnwrap(try encoded(json)["paymentMethod"] as? [String: Any])

            XCTAssertEqual(method["type"] as? String, expected)
        }
    }

    /// A card with neither name nor network still produces a body. The two are
    /// optional on `PKPaymentMethod`, and emitting `null` for them would be a
    /// different thing at the edge from omitting them.
    func testAnAnonymousCardOmitsTheFieldsItHasNothingFor() throws {
        let token = StubPaymentToken(
            method: StubPaymentMethod(type: .debit, displayName: nil, network: nil)
        )
        let method = try XCTUnwrap(
            try encoded(try XCTUnwrap(PassKitWalletAuthorizer.tokenJSON(token)))["paymentMethod"]
                as? [String: Any]
        )

        XCTAssertEqual(Set(method.keys), ["type"])
    }

    /// Bytes that are not JSON cannot be forwarded, and the adapter reports
    /// that rather than sending an empty body the vault would reject.
    func testATokenThatIsNotJSONConvertsToNothing() {
        let token = StubPaymentToken(paymentData: Data("not json at all".utf8))

        XCTAssertNil(PassKitWalletAuthorizer.tokenJSON(token))
    }

    // MARK: - Helpers

    /// Joins the waiting task, but only when it actually resumed.
    ///
    /// Awaiting unconditionally would turn the regression these tests exist to
    /// catch -- a `didFinish` that never resumes -- from a failed assertion
    /// into a run that hangs until xcodebuild gives up, which reports nothing
    /// and costs everyone ten minutes. A suspended task is simply abandoned;
    /// the runtime logs a leaked continuation and the suite moves on.
    private func settle(_ waiter: Task<Void, Never>, resumed: Bool) async {
        guard resumed else { return waiter.cancel() }
        _ = await waiter.value
    }

    /// Encodes a `JSONValue` and reads it back as a dictionary, so every
    /// assertion above is against the JSON that goes on the wire rather than
    /// against the enum the SDK happens to hold.
    private func encoded(_ value: JSONValue) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

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

/// A `PKPaymentToken` with the fields PassKit would have filled in.
///
/// Subclassed rather than constructed: PassKit hands these out and has no
/// public initialiser that fills them, so the only alternative to a subclass is
/// leaving the conversion executed by nothing but a real device. Both classes
/// are Objective-C and every property here is readonly and overridable.
private final class StubPaymentToken: PKPaymentToken {
    private let stubData: Data
    private let stubMethod: PKPaymentMethod
    private let stubTransactionIdentifier: String

    init(
        paymentData: Data = Data(StubPaymentToken.paymentDataJSON.utf8),
        method: PKPaymentMethod = StubPaymentMethod(),
        transactionIdentifier: String = "31323334353637383930"
    ) {
        self.stubData = paymentData
        self.stubMethod = method
        self.stubTransactionIdentifier = transactionIdentifier
        super.init()
    }

    override var paymentData: Data { stubData }
    override var paymentMethod: PKPaymentMethod { stubMethod }
    override var transactionIdentifier: String { stubTransactionIdentifier }

    /// Carries an unknown key on purpose: the passthrough exists so a field
    /// Apple adds without telling anyone still reaches the vault.
    static let paymentDataJSON = #"""
    {
      "version": "EC_v1",
      "data": "4rMLBQ-encrypted-payload",
      "signature": "MEUCIQD-signature-bytes",
      "somethingAppleAddedLater": "kept",
      "header": {
        "ephemeralPublicKey": "MFkwEw-ephemeral-key",
        "publicKeyHash": "LbsUwAT6w1JV9tFXocU813TCHks+LSuFF0R/eBkrWnQ=",
        "transactionId": "31323334353637383930"
      }
    }
    """#
}

private final class StubPaymentMethod: PKPaymentMethod {
    private let stubType: PKPaymentMethodType
    private let stubDisplayName: String?
    private let stubNetwork: PKPaymentNetwork?

    init(
        type: PKPaymentMethodType = .credit,
        displayName: String? = "Visa 1234",
        network: PKPaymentNetwork? = .visa
    ) {
        self.stubType = type
        self.stubDisplayName = displayName
        self.stubNetwork = network
        super.init()
    }

    override var type: PKPaymentMethodType { stubType }
    override var displayName: String? { stubDisplayName }
    override var network: PKPaymentNetwork? { stubNetwork }
}

@MainActor
private final class OutcomeBox {
    var value: WalletAuthorizationOutcome?
}
#endif
