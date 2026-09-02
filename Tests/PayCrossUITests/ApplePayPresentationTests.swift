#if os(iOS)
import XCTest
import PassKit
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

/// Pins the parts of the Apple Pay branch that only a running iOS process can
/// prove: that Apple's button is in the view hierarchy exactly when the model
/// says it should be, that a tap reaches the model, that the model hands the
/// authorizer the session's own numbers, and that field groups are validated
/// before the sheet rather than after.
///
/// The simulator cannot make a real Apple Pay payment -- there is no
/// entitlement under `CODE_SIGNING_ALLOWED=NO` and a simulator Wallet returns a
/// stub token the vault refuses -- so nothing here asserts on a payment. What
/// is asserted is which code runs and what it is handed.
@MainActor
final class ApplePayPresentationTests: XCTestCase {

    private static let hostSize = CGSize(width: 390, height: 844) // iPhone 17 portrait

    /// Held for the duration of the test; a released window takes the hierarchy
    /// under test with it.
    ///
    /// No `tearDown()` override clearing it, unlike `ThreeDSPresentationTests`:
    /// `tearDown()` is a nonisolated override and this class is `@MainActor`, so
    /// touching main-actor state from it is a Swift 6 diagnostic that can only
    /// be silenced with an escape hatch. XCTest holds one instance per test
    /// method for the length of the run, which is three windows here, and they
    /// go when the suite does.
    private var windows: [UIWindow] = []

    // MARK: - The button in the hierarchy

    /// Hosts the card form in a real window and lets SwiftUI commit its layout,
    /// so the `UIViewRepresentable` actually makes its `PKPaymentButton`.
    private func hostForm(
        showsApplePayButton: Bool,
        isLoading: Bool = false,
        onApplePay: @escaping () -> Void = {}
    ) -> UIWindow {
        let controller = UIHostingController(
            rootView: FormHarness(
                showsApplePayButton: showsApplePayButton,
                isLoading: isLoading,
                onApplePay: onApplePay
            )
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.hostSize))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        windows.append(window)

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return window
    }

    func testTheButtonIsInTheHierarchyWhenTheFormIsToldToShowIt() throws {
        let window = hostForm(showsApplePayButton: true)
        XCTAssertNotNil(
            firstSubview(PKPaymentButton.self, in: window),
            "the card form must render Apple's own control, not a lookalike"
        )
    }

    /// The negative half. Without it the test above passes against a form that
    /// always draws the button.
    func testTheButtonIsAbsentWhenTheFormIsNotToldToShowIt() throws {
        let window = hostForm(showsApplePayButton: false)
        XCTAssertNil(
            firstSubview(PKPaymentButton.self, in: window),
            "a form told not to offer Apple Pay must not have the button in it at all"
        )
    }

    /// The primary action of the whole feature must not lie about its state.
    ///
    /// For the submit-and-poll phase, which this file's own comments say can
    /// run to a deadline of minutes, the button was fully lit and did nothing
    /// when tapped, because the model's re-entry guard swallowed it. The
    /// spinner is on the card button, which is not the control the shopper is
    /// looking at.
    func testTheButtonIsDisabledWhileAPaymentIsInFlight() throws {
        let busy = hostForm(showsApplePayButton: true, isLoading: true)
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: busy))

        // Asserted on `isUserInteractionEnabled` rather than `isEnabled`,
        // because PKPaymentButton ignores the latter -- measured, not assumed:
        // with both set false on the same view, the alpha changed and
        // `isEnabled` still read true.
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

    /// SwiftUI puts `.accessibilityIdentifier` on its own accessibility node,
    /// not on the wrapped control, so anything walking `UIView`s -- a UI test,
    /// the demo harness in task 08 -- finds nothing without this.
    func testTheButtonCarriesItsIdentifierOnTheControlItself() throws {
        let window = hostForm(showsApplePayButton: true)
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: window))

        XCTAssertEqual(button.accessibilityIdentifier, "applePayButton")
    }

    func testTappingTheButtonRunsTheAction() throws {
        let taps = Counter()
        let window = hostForm(showsApplePayButton: true) { taps.value += 1 }
        let button = try XCTUnwrap(firstSubview(PKPaymentButton.self, in: window))

        // Dispatched through the registered target-action pair rather than
        // `sendActions(for: .touchUpInside)`. That call routes through
        // UIApplication's event machinery, an xctest bundle with no host app
        // has no UIApplication object, and the count stays zero however well
        // the button is wired -- measured, not assumed. Reaching for the pair
        // is the route ThreeDSPresentationTests already uses for the
        // challenge's Cancel, and it asserts strictly more: that a target is
        // registered for a tap at all, and that the selector on it is the one
        // the view installed.
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

    /// The positive row, and the one that makes the four negatives mean
    /// anything. On a simulator the real `canMakePayments` is always false --
    /// a fresh device has an empty Wallet -- so a model that asked PassKit
    /// directly would answer "no button" to every question here and every
    /// negative row would pass for a reason that has nothing to do with what
    /// it claims to test.
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

    /// The gate's `data:` argument, exercised at the model level. This is the
    /// only test that needs the initialiser's `sessionData:` seam: the
    /// published property is `private(set)` and `@testable` does not defeat
    /// that, and its only other writer is reached through a real network call.
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

    /// A session that never loaded is not a session with no opinion.
    ///
    /// Core's gate answers `true` for nil data on purpose, because an absent
    /// `wallets` block means the server said nothing and every snapshot minted
    /// before the backend shipped that block reads that way. But `load()`
    /// swallows a transport failure and a 5xx alike, so nil is also what a
    /// session that never arrived looks like -- and the request spec needs the
    /// session's own currency and amount. Rendering here would offer a button
    /// that opens onto nothing.
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
        // Hoisted out of XCTUnwrap: its argument is an autoclosure and cannot await.
        let recorded = await firstSpec(from: authorizer)
        let spec = try XCTUnwrap(recorded, "the authorizer was never called")

        XCTAssertEqual(spec.merchantIdentifier, "merchant.pay-cross.com")
        XCTAssertEqual(spec.countryCode, "GB")
        XCTAssertEqual(spec.currencyCode, "EUR")
        XCTAssertEqual(spec.amount.minorUnits, 2599)
    }

    /// The identifier is trimmed before it becomes payload.
    ///
    /// `WalletGate.offersApplePay` trims before answering and
    /// `WalletToken.applePay` trims before building the submit body, so a
    /// padded value left untrimmed here would put a merchant identifier Apple
    /// cannot match on the `PKPaymentRequest` beside a body carrying the right
    /// one. The sheet would never open and the only report would be that Apple
    /// Pay could not be presented.
    func testAPaddedIdentifierReachesTheSheetTrimmed() async throws {
        let authorizer = FakeWalletAuthorizer(outcome: .cancelled)
        let model = makeModel(
            sessionData: SessionData(wallets: WalletsAvailability(applePay: true)),
            merchantIdentifier: "  merchant.pay-cross.com\n",
            deviceCanPay: true,
            authorizer: authorizer
        )

        model.payWithApplePay()
        // Hoisted out of XCTUnwrap: its argument is an autoclosure and cannot await.
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

        // Resume the sheet's own continuation so the test does not leak it.
        model.cancel()
        _ = await waiter.value
    }

    /// The ordering the design is explicit about, asserted the only way that
    /// distinguishes it: a **zero** call count. Asserting that an error appeared
    /// would pass just as well against a sheet that opened first and validated
    /// afterwards, which is exactly the failure this ordering exists to
    /// prevent -- core rejects those field groups server-side, so the shopper
    /// would have spent a Face ID authorisation on a rejection they could have
    /// been shown before the sheet.
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
        // Long enough that a sheet opened before validation would have been
        // recorded by now.
        _ = await waitUntil(timeout: 0.5) { await authorizer.callCount > 0 }

        let calls = await authorizer.callCount
        XCTAssertEqual(calls, 0, "Apple's sheet must not open for a payment the server will reject")
        XCTAssertFalse(model.fieldErrors.isEmpty, "the shopper must be told which field is wrong")
        XCTAssertFalse(model.isLoading, "a payment that never started must not leave the form locked")
    }

    // MARK: - Helpers

    private func makeModel(
        sessionData: SessionData?,
        merchantIdentifier: String?,
        deviceCanPay: Bool,
        amount: Amount = Amount(minorUnits: 2599, currencyCode: "EUR"),
        authorizer: (any WalletAuthorizing)? = nil
    ) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil, amount: amount, expiresAt: nil
            ),
            // Read off the model, never off PayCrossAPI: the static
            // configuration is a process-wide box nothing resets, and this
            // target also runs ScreenshotTests and ThreeDSPresentationTests.
            configuration: Configuration(
                environment: .sandbox,
                testCardPrefill: nil,
                applePayMerchantIdentifier: merchantIdentifier
            ),
            walletAuthorizer: authorizer,
            deviceCanPay: { deviceCanPay },
            sessionData: sessionData
        )
    }

    private func firstSpec(from authorizer: FakeWalletAuthorizer) async -> ApplePayRequestSpec? {
        _ = await waitUntil { await authorizer.callCount > 0 }
        return await authorizer.received.first
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
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

/// Records every spec it is asked to authorize.
///
/// An actor rather than a class with a lock, and certainly rather than
/// `@unchecked Sendable`: `WalletAuthorizing` is `Sendable`, the fake holds
/// mutable state, and normalising the escape hatch into the test target is how
/// it ends up in the SDK.
///
/// Recording is the point. A fake that only answers makes every test compile
/// and proves nothing about what Apple was asked for.
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

/// Boxed so an escaping closure and the assertions read the same value.
@MainActor
private final class Counter {
    var value = 0
}

@MainActor
private final class ResultBox {
    var value: PaymentResult?
}

/// Supplies the two bindings `CardFormView` needs in a context that has no
/// `@State` of its own.
private struct FormHarness: View {
    let showsApplePayButton: Bool
    let isLoading: Bool
    let onApplePay: () -> Void

    @State private var state = CardFormState()
    @State private var fieldValues: [String: [String: String]] = [:]

    var body: some View {
        CardFormView(
            state: $state,
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            savedCards: [],
            allowsSaving: false,
            isLoading: isLoading,
            fieldGroups: [],
            fieldValues: $fieldValues,
            fieldErrors: [],
            onPay: {},
            showsApplePayButton: showsApplePayButton,
            onApplePay: onApplePay
        )
    }
}
#endif
