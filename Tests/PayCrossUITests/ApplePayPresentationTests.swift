#if os(iOS)
import XCTest
import PassKit
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class ApplePayPresentationTests: XCTestCase {


    private let host = ViewHost()

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

    // MARK: - The button in the hierarchy

    private func hostForm(
        showsApplePayButton: Bool,
        isLoading: Bool = false,
        onApplePay: @escaping () -> Void = {}
    ) -> UIWindow {
        return host(
            FormHarness(
                showsApplePayButton: showsApplePayButton,
                isLoading: isLoading,
                onApplePay: onApplePay
            )
        )
    }

    func testTheButtonIsInTheHierarchyWhenTheFormIsToldToShowIt() throws {
        let window = hostForm(showsApplePayButton: true)
        XCTAssertNotNil(
            firstSubview(PKPaymentButton.self, in: window),
            "the card form must render Apple's own control, not a lookalike"
        )
    }

    func testTheButtonIsAbsentWhenTheFormIsNotToldToShowIt() throws {
        let window = hostForm(showsApplePayButton: false)
        XCTAssertNil(
            firstSubview(PKPaymentButton.self, in: window),
            "a form told not to offer Apple Pay must not have the button in it at all"
        )
    }

    func testTheButtonIsDisabledWhileAPaymentIsInFlight() throws {
        let busy = hostForm(showsApplePayButton: true, isLoading: true)
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: busy))

        XCTAssertFalse(
            button.isUserInteractionEnabled,
            "a lit button that does nothing when tapped is worse than a dim one"
        )
        XCTAssertLessThan(button.alpha, 1, "it must also look unavailable, not merely refuse taps")
    }

    func testTheButtonIsLiveWhenNoPaymentIsInFlight() throws {
        let idle = hostForm(showsApplePayButton: true, isLoading: false)
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: idle))

        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertEqual(button.alpha, 1, accuracy: 0.001)
    }

    func testTheButtonCarriesItsIdentifierOnTheControlItself() throws {
        let window = hostForm(showsApplePayButton: true)
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: window))

        XCTAssertEqual(button.accessibilityIdentifier, PayCrossTestIdentifiers.walletButton.rawValue)
    }

    func testTappingTheButtonRunsTheAction() throws {
        let taps = Counter()
        let window = hostForm(showsApplePayButton: true) { taps.value += 1 }
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: window))

        let target = try XCTUnwrap(
            button.allTargets.first as? NSObject,
            "Apple's button has no target, so a tap would go nowhere"
        )
        let action = try XCTUnwrap(
            button.actions(forTarget: target, forControlEvent: .touchUpInside)?.first,
            "Apple's button has no action registered for a tap"
        )
        target.perform(Selector(action))

        XCTAssertEqual(taps.value, 1, "a tap on Apple's button must reach the sheet's model")
    }

    // MARK: - The model's visibility rule, one truth table

    func testTheModelOffersTheButtonWhenEveryConditionHolds() {
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true
        )
        XCTAssertTrue(model.showsApplePayButton)
    }

    func testNoConfiguredIdentifierMeansNoButton() {
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: nil,
            deviceCanPay: true
        )
        XCTAssertFalse(model.showsApplePayButton)
    }

    func testASessionThatSaysApplePayFalseMeansNoButton() {
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: false)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true
        )
        XCTAssertFalse(model.showsApplePayButton)
    }

    func testADeviceWithNoCardMeansNoButton() {
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: false
        )
        XCTAssertFalse(model.showsApplePayButton)
    }

    func testASessionThatNeverLoadedMeansNoButton() {
        let model = makeModel(
            sessionData: nil,
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true
        )
        XCTAssertFalse(model.showsApplePayButton)
        XCTAssertTrue(
            WalletGate.allowsApplePay(nil),
            "Core's gate must stay permissive about a nil snapshot; the render rule is this layer's"
        )
    }

    // MARK: - What the authorizer is handed

    func testTheAuthorizerIsHandedTheSessionsOwnRequestSpec() async throws {
        let authorizer = FakeWalletAuthorizer(outcome: .cancelled)
        let model = makeModel(
            sessionData: SessionData(merchantCountry: "GB", wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true,
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            authorizer: authorizer
        )

        model.payWithApplePay()
        let recorded = await firstSpec(from: authorizer)
        let spec = try XCTUnwrap(recorded, "the authorizer was never called")

        XCTAssertEqual(spec.merchantIdentifier, "merchant.pay-cross.com")
        XCTAssertEqual(spec.countryCode, "GB")
        XCTAssertEqual(spec.currencyCode, "EUR")
        XCTAssertEqual(spec.amount.minorUnits, 2599)
    }

    func testAPaddedIdentifierReachesTheSheetTrimmed() async throws {
        let authorizer = FakeWalletAuthorizer(outcome: .cancelled)
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "  merchant.pay-cross.com\n",
            deviceCanPay: true,
            authorizer: authorizer
        )

        model.payWithApplePay()
        let recorded = await firstSpec(from: authorizer)
        let spec = try XCTUnwrap(recorded, "the authorizer was never called")

        XCTAssertEqual(spec.merchantIdentifier, "merchant.pay-cross.com")
    }

    func testACancelledSheetEmitsNoResultAndLeavesTheFormUsable() async throws {
        let authorizer = FakeWalletAuthorizer(outcome: .cancelled)
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true,
            authorizer: authorizer
        )

        let delivered = ResultBox()
        let waiter = Task { @MainActor in delivered.value = await model.awaitResult() }

        model.payWithApplePay()
        let recorded = await firstSpec(from: authorizer)
        _ = try XCTUnwrap(recorded, "the authorizer was never called")
        _ = await waitUntil { model.isLoading == false }

        XCTAssertNil(delivered.value, "dismissing Apple's sheet is not a payment outcome")
        XCTAssertFalse(model.isLoading, "the shopper is back on the card form and it must be usable")
        XCTAssertNil(model.form.inlineError, "a cancel is not an error and must not be shown as one")

        model.cancel()
        _ = await waiter.value
    }

    func testInvalidFieldGroupsNeverReachTheAuthorizer() async {
        let authorizer = FakeWalletAuthorizer(outcome: .cancelled)
        let groups = [FieldGroup(key: "billing", label: "Billing address", fields: [
            FieldDefinition(name: "postcode", type: "text", label: "Postcode", required: true)
        ])]
        let model = makeModel(
            sessionData: SessionData(
                fieldGroups: groups,
                wallets: WalletsAvailability(applePay: true)
            ),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true,
            authorizer: authorizer
        )

        model.payWithApplePay()
        _ = await waitUntil(timeout: 0.5) { await authorizer.callCount > 0 }

        let calls = await authorizer.callCount
        XCTAssertEqual(calls, 0, "Apple's sheet must not open for a payment the server will reject")
        XCTAssertFalse(model.fieldErrors.isEmpty, "the shopper must be told which field is wrong")
        XCTAssertFalse(model.isLoading, "a payment that never started must not leave the form locked")
    }

    // MARK: - The join between the model and the sheet

    func testTheSheetShowsTheButtonWhenTheLoadedSessionAllowsIt() async throws {
        let (window, model) = hostSheet(merchantIdentifier: "merchant.pay-cross.com")

        let loaded = await waitUntil { model.sessionData != nil }
        XCTAssertTrue(loaded, "the stub session never reached the model")
        XCTAssertTrue(model.showsApplePayButton, "the model must want the button for this to prove anything")

        let appeared = await waitUntil { self.firstSubview(PKPaymentButton.self, in: window) != nil }
        XCTAssertTrue(appeared, "the sheet must pass the model's answer into the form")
    }

    func testTheSheetHidesTheButtonWhenNoIdentifierIsConfigured() async throws {
        let (window, model) = hostSheet(merchantIdentifier: nil)

        let loaded = await waitUntil { model.sessionData != nil }
        XCTAssertTrue(loaded, "the stub session never reached the model")
        XCTAssertFalse(model.showsApplePayButton)

        window.layoutIfNeeded()
        let appeared = await waitUntil(timeout: 1) {
            self.firstSubview(PKPaymentButton.self, in: window) != nil
        }
        XCTAssertFalse(appeared, "no identifier means the sheet must never offer the button")
    }

    // MARK: - The authorised path

    func testAnAuthorizedTokenReachesTheSubmitBodyVerbatim() async throws {
        let token = try JSONDecoder().decode(JSONValue.self, from: Data(Self.appleTokenJSON.utf8))
        let transport = StubTransport(replies: [
            .init(body: Data(#"{"success":true,"transaction_id":"txn_1"}"#.utf8)),
            .init(body: Data(#"{"transaction_id":"txn_1","status":"success"}"#.utf8))
        ])
        let model = makeModel(
            sessionData: SessionData(merchantCountry: "GB", wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true,
            authorizer: FakeWalletAuthorizer(outcome: .authorized(token)),
            transport: transport
        )

        let delivered = ResultBox()
        let waiter = Task { @MainActor in delivered.value = await model.awaitResult() }
        model.payWithApplePay()

        let finished = await waitUntil { delivered.value != nil }
        XCTAssertTrue(finished, "the authorised payment never reached a terminal state")
        XCTAssertEqual(
            delivered.value,
            .succeeded(
                transactionID: "txn_1", status: "success",
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                savedCardToken: nil
            ),
            "an Apple Pay payment completes through the same callback as a card payment"
        )

        let sent = await transport.sent
        let submitted = try XCTUnwrap(sent.first?.httpBody, "nothing was submitted")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: submitted) as? [String: Any])

        XCTAssertEqual(body["payment_method"] as? String, "apple_pay")
        XCTAssertNil(body["card"], "a wallet body must never also carry a card")

        let wallet = try XCTUnwrap(body["wallet_token"] as? [String: Any])
        XCTAssertEqual(wallet["type"] as? String, "apple_pay")
        XCTAssertTrue(wallet.keys.contains("merchant_identifier"))
        let identifier = try XCTUnwrap(wallet["merchant_identifier"] as? String)
        XCTAssertEqual(identifier, "merchant.pay-cross.com")
        XCTAssertFalse(identifier.isEmpty)

        let data = try XCTUnwrap(wallet["data"] as? [String: Any])
        let paymentData = try XCTUnwrap(data["paymentData"] as? [String: Any])
        let header = try XCTUnwrap(paymentData["header"] as? [String: Any])
        XCTAssertEqual(paymentData["version"] as? String, "EC_v1")
        XCTAssertEqual(paymentData["signature"] as? String, "MEUCIQD-signature-bytes")
        XCTAssertEqual(paymentData["data"] as? String, "4rMLBQ-encrypted-payload")
        XCTAssertEqual(header["publicKeyHash"] as? String, "LbsUwAT6w1JV9tFXocU813TCHks+LSuFF0R/eBkrWnQ=")
        XCTAssertEqual(header["transactionId"] as? String, "31323334353637383930")
        XCTAssertEqual(header["ephemeralPublicKey"] as? String, "MFkwEw-ephemeral-key")
        let method = try XCTUnwrap(data["paymentMethod"] as? [String: Any])
        XCTAssertEqual(method["network"] as? String, "Visa")
        XCTAssertEqual(method["type"] as? String, "credit")
        XCTAssertEqual(method["displayName"] as? String, "Visa 1234")
        XCTAssertEqual(data["transactionIdentifier"] as? String, "31323334353637383930")

        _ = await waiter.value
    }

    func testABackendRejectionSurfacesLikeACardDecline() async throws {
        let token = try JSONDecoder().decode(JSONValue.self, from: Data(Self.appleTokenJSON.utf8))
        let transport = StubTransport(replies: [
            .init(status: 400, body: Data(#"{"error":"merchant identifier mismatch"}"#.utf8))
        ])
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "merchant.pay-cross.com",
            deviceCanPay: true,
            authorizer: FakeWalletAuthorizer(outcome: .authorized(token)),
            transport: transport
        )

        let delivered = ResultBox()
        let waiter = Task { @MainActor in delivered.value = await model.awaitResult() }
        model.payWithApplePay()

        let rearmed = await waitUntil { model.form.inlineError != nil }
        XCTAssertTrue(rearmed, "a rejected wallet payment must re-arm the form the way a card decline does")
        XCTAssertFalse(model.isLoading, "the shopper must be able to try again")
        XCTAssertNil(delivered.value, "a re-armed form is not a terminal result")

        model.cancel()
        _ = await waiter.value
    }

    // MARK: - Helpers

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

    private static let openSessionJSON = #"""
    {"session_id":"sess_1","status":"open",
     "data":{"merchant_country":"GB","wallets":{"apple_pay":true}}}
    """#

    private func hostSheet(merchantIdentifier: String?) -> (UIWindow, PaymentSheetModel) {
        let model = makeModel(
            sessionData: nil,
            merchantIdentifier: merchantIdentifier,
            deviceCanPay: true,
            transport: StubTransport(json: Self.openSessionJSON),
            isPreparing: false
        )

        return (host(PaymentSheetView(model: model)), model)
    }

    private func makeModel(
        sessionData: SessionData?,
        merchantIdentifier: String?,
        deviceCanPay: Bool,
        amount: Amount = Amount(minorUnits: 2599, currencyCode: "EUR"),
        authorizer: (any WalletAuthorizing)? = nil,
        transport: any HTTPTransport = StubTransport(status: 500),
        isPreparing: Bool = true
    ) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil, amount: amount, expiresAt: nil
            ),
            configuration: Configuration(
                environment: .sandbox,
                testCardPrefill: nil,
                applePayMerchantIdentifier: merchantIdentifier
            ),
            walletAuthorizer: authorizer,
            deviceCanPay: { deviceCanPay },
            sessionData: sessionData,
            isPreparing: isPreparing,
            transport: transport
        )
    }

    private func firstSpec(from authorizer: FakeWalletAuthorizer) async -> ApplePayRequestSpec? {
        _ = await waitUntil { await authorizer.callCount > 0 }
        return await authorizer.received.first
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

    private func firstSubview<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(type, in: subview) { return match }
        }
        return nil
    }
}

private actor FakeWalletAuthorizer: WalletAuthorizing {
    private(set) var received: [ApplePayRequestSpec] = []
    private let outcome: WalletAuthorizationOutcome

    var callCount: Int { received.count }

    init(outcome: WalletAuthorizationOutcome) {
        self.outcome = outcome
    }

    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome {
        received.append(spec)
        return outcome
    }
}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
private final class ResultBox {
    var value: PaymentResult?
}

private struct FormHarness: View {
    let showsApplePayButton: Bool
    let isLoading: Bool
    let onApplePay: () -> Void

    @State private var state = CardFormState()
    @State private var fieldValues: [String: [String: String]] = [:]
    @State private var optedInGroups: Set<String> = []

    var body: some View {
        CardFormView(
            state: $state,
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: isLoading,
            fieldGroups: [],
            fieldValues: $fieldValues,
            optedInGroups: $optedInGroups,
            fieldErrors: [],
            language: SheetLanguage.tag,
            onPay: {},
            showsApplePayButton: showsApplePayButton,
            onApplePay: onApplePay
        )
    }
}
#endif
