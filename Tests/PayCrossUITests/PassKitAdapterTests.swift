#if os(iOS)
import XCTest
import PassKit
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class PassKitAdapterTests: XCTestCase {

    private var originalUserAgentProvider: UserAgentProvider!

    override func setUp() {
        super.setUp()
        originalUserAgentProvider = DeviceInfo.userAgentProvider
        DeviceInfo.userAgentProvider = { "Mozilla/5.0 (iPhone) StubAgent/1.0" }
    }

    override func tearDown() async throws {
        DeviceInfo.userAgentProvider = originalUserAgentProvider
        try await super.tearDown()
    }


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

    func testTheRequestCarriesEveryNetworkTheSpecNames() {
        let request = PassKitWalletAuthorizer.makeRequest(spec())

        XCTAssertEqual(
            Set(request.supportedNetworks),
            Set([PKPaymentNetwork.visa, .masterCard, .amex, .discover, .JCB])
        )
    }

    func testTheRequestKeepsTheThreeDSecureCapability() {
        let request = PassKitWalletAuthorizer.makeRequest(spec())

        XCTAssertTrue(
            request.merchantCapabilities.contains(.capability3DS),
            "Apple requires 3-D Secure for in-app payments; without it no sheet ever opens"
        )
        XCTAssertTrue(request.merchantCapabilities.contains(.capabilityCredit))
        XCTAssertTrue(request.merchantCapabilities.contains(.capabilityDebit))
    }

    func testTheSummaryItemQuotesTheAmountInMajorUnits() throws {
        let request = PassKitWalletAuthorizer.makeRequest(spec())
        let item = try XCTUnwrap(request.paymentSummaryItems.first)

        XCTAssertEqual(request.paymentSummaryItems.count, 1)
        XCTAssertEqual(item.label, "Total")
        XCTAssertEqual(item.type, .final)
        XCTAssertEqual(item.amount, NSDecimalNumber(string: "25.99"))
    }

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

    func testASecondAuthorizeIsRefusedWhileASheetIsOpen() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }
        _ = await waitUntil { authorizer.isAwaitingOutcome }

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

    func testASecondWaitOnTheDelegateIsRefused() async throws {
        let authorizer = PassKitWalletAuthorizer()
        let box = OutcomeBox()
        let waiter = Task { @MainActor in box.value = await authorizer.awaitDelegateOutcome() }
        _ = await waitUntil { authorizer.isAwaitingOutcome }

        let secondBox = OutcomeBox()
        let second = Task { @MainActor in secondBox.value = await authorizer.awaitDelegateOutcome() }
        let answered = await waitUntil { secondBox.value != nil }

        XCTAssertTrue(answered, "a second wait must be refused at once, not queued behind the first")
        XCTAssertEqual(secondBox.value, .failed("An Apple Pay sheet is already open."))
        XCTAssertTrue(authorizer.isAwaitingOutcome, "the first caller must still be waiting")
        await settle(second, resumed: answered)

        authorizer.paymentAuthorizationControllerDidFinish(stubController())
        let resumed = await waitUntil { box.value != nil }
        XCTAssertEqual(box.value, .cancelled, "the first caller must still get its own answer")
        await settle(waiter, resumed: resumed)
    }

    // MARK: - The token, as PassKit hands it over

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

    func testAnUnknownFieldInsideTheTokenSurvives() throws {
        let json = try XCTUnwrap(PassKitWalletAuthorizer.tokenJSON(StubPaymentToken()))
        let paymentData = try XCTUnwrap(try encoded(json)["paymentData"] as? [String: Any])

        XCTAssertEqual(
            paymentData["somethingAppleAddedLater"] as? String, "kept",
            "the token is carried through, not modelled; a dropped unknown field is a decryption failure with no field to point at"
        )
    }

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

    func testATokenThatIsNotJSONConvertsToNothing() {
        let token = StubPaymentToken(paymentData: Data("not json at all".utf8))

        XCTAssertNil(PassKitWalletAuthorizer.tokenJSON(token))
    }

    // MARK: - Helpers

    private func settle(_ waiter: Task<Void, Never>, resumed: Bool) async {
        guard resumed else { return waiter.cancel() }
        _ = await waiter.value
    }

    private func encoded(_ value: JSONValue) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func waitUntil(
        timeout: TimeInterval = 30,
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
