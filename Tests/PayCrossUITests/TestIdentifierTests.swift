#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// The identifier contract: the strings themselves, and the ones a hosted tree
/// can be made to admit to.
///
/// **What this cannot reach.** SwiftUI builds its accessibility elements only
/// when the test bundle runs inside an app host. `PayCrossUITests` is a SwiftPM
/// test target, which `xctest` loads with no host, so a `Text` or a `Button`
/// carrying `.accessibilityIdentifier` appears nowhere in the hosted hierarchy —
/// measured: the hosting view answers `accessibilityElements` with an empty
/// array. The UIKit-backed leaves are a different matter, because their
/// identifier is set on a `UIView` that exists whether anything is reading the
/// accessibility tree or not, and those are asserted below on a real render.
///
/// The rest is held by three other things: the Invariants job greps that every
/// case in `PayCrossTestIdentifiers` is applied somewhere in `Sources/PayCross`
/// and that no 0.6.0 flat name survives; the campaign's E2E driver addresses the
/// sheet by these strings through WebDriverAgent, which is a real accessibility
/// client in a real app; and the screenshots show the rendered result.
@MainActor
final class TestIdentifierTests: XCTestCase {

    private let host = ViewHost()

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - The strings

    func testEveryIdentifierIsPrefixedAndCamelCased() {
        for identifier in PayCrossTestIdentifiers.allCases {
            XCTAssertTrue(
                identifier.rawValue.hasPrefix("paycross."),
                "\(identifier.rawValue) is not in the paycross namespace"
            )
            let tail = identifier.rawValue.dropFirst("paycross.".count)
            XCTAssertFalse(tail.isEmpty, "\(identifier.rawValue) names nothing")
            XCTAssertFalse(tail.contains("."), "\(identifier.rawValue) has a second segment")
            XCTAssertFalse(tail.contains("_"), "\(identifier.rawValue) is not camelCase")
            XCTAssertFalse(tail.contains("-"), "\(identifier.rawValue) is not camelCase")
            XCTAssertFalse(
                tail.first?.isUppercase ?? true, "\(identifier.rawValue) is not camelCase"
            )
        }
    }

    func testNoTwoElementsShareAnIdentifier() {
        let raw = PayCrossTestIdentifiers.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raw).count, raw.count)
    }

    /// The composed ones are Android's strings character for character.
    /// `SavedCard.id` is filled from the wire's `uuid`, which is the field
    /// Android tags its rows with, so one string addresses one card on both.
    func testTheComposedIdentifiersMatchTheAndroidStrings() {
        let uuid = "6f1c9c3e-0d5a-4a3f-9c2b-4d0e1f2a3b4c"
        XCTAssertEqual(
            PayCrossTestIdentifiers.savedCard(uuid), "paycross.savedCard.\(uuid)"
        )
        XCTAssertEqual(
            PayCrossTestIdentifiers.savedCardDelete(uuid), "paycross.savedCard.\(uuid).delete"
        )
        XCTAssertEqual(
            PayCrossTestIdentifiers.field(group: "billing", name: "postcode"),
            "paycross.field.billing.postcode"
        )
        XCTAssertEqual(
            PayCrossTestIdentifiers.fieldError(group: "billing", name: "postcode"),
            "paycross.field.billing.postcode.error"
        )
    }

    /// The pin on the one rule these strings cannot express.
    ///
    /// The dot is the separator and nothing escapes it, so a dotted component
    /// collides with the pair beside it. Both halves are our own wire keys —
    /// snake_case names the server sends in `field_groups` — where a dot has
    /// never been valid, and Android joins the same way, so an escaping rule
    /// would have to be invented on both platforms and kept identical for one
    /// identifier to keep naming one field.
    ///
    /// This asserts the collision rather than a fix for it. Anyone who starts
    /// allowing a dot in a group key or a field name lands here, and can go and
    /// change Android in the same breath.
    func testADottedComponentCollides() {
        XCTAssertEqual(
            PayCrossTestIdentifiers.field(group: "a.b", name: "c"),
            PayCrossTestIdentifiers.field(group: "a", name: "b.c"),
            "a dot is now escaped on iOS; Android must be changed to match"
        )
    }

    /// The row identifier is built from the card's own id and nothing else, so
    /// a session that lists two cards produces two distinct handles.
    func testEachStoredCardGetsAHandleOfItsOwn() {
        let first = SavedCard(id: "a", brand: .visa, last4: "0366", expiryLabel: "03/29")
        let second = SavedCard(id: "b", brand: .visa, last4: "0366", expiryLabel: "03/29")
        XCTAssertNotEqual(
            PayCrossTestIdentifiers.savedCard(first.id),
            PayCrossTestIdentifiers.savedCard(second.id),
            "two cards that differ only by uuid must not share a row identifier"
        )
    }

    // MARK: - The rendered tree

    /// The four UIKit-backed controls, on a real render: three card fields and
    /// Apple's own button.
    func testTheUIKitBackedControlsPublishTheirIdentifiers() throws {
        let window = hostForm(showsApplePayButton: true)
        let found = identifiers(in: window)

        for expected: PayCrossTestIdentifiers in [.cardNumber, .expiry, .cvv, .walletButton] {
            XCTAssertTrue(
                found.contains(expected.rawValue),
                "\(expected.rawValue) is not on the rendered tree; found \(found.sorted())"
            )
        }
    }

    /// The 0.6.0 names are gone from the same render rather than merely joined
    /// by the new ones.
    func testTheFlatNamesTheseReplacedAreGone() throws {
        let window = hostForm(showsApplePayButton: true)
        let found = identifiers(in: window)

        for old in ["cardNumber", "expiry", "cvv", "applePayButton"] {
            XCTAssertFalse(found.contains(old), "\(old) is still published")
        }
    }

    /// Neither confirmation may be a system alert.
    ///
    /// This is the measurement `ConfirmationDialog` exists for. With the cancel
    /// confirmation open through `.alert`, the presented `UIAlertController`
    /// answered `accessibilityIdentifier` with nil on both of its actions and
    /// carried none anywhere in its view tree, so the four button identifiers
    /// the README promises could not be reached by name. Drawn in the sheet
    /// they are ordinary SwiftUI identifiers, like the Pay button's.
    ///
    /// Nothing presented over the sheet is what that comes down to, and it is
    /// the one half of it a unit test can hold.
    func testAConfirmationIsDrawnInTheSheetRatherThanPresentedOverIt() throws {
        let model = makeModel(isPreparing: false)
        let window = host(PaymentSheetView(model: model))

        model.isConfirmingCancel = true
        host.settle()

        XCTAssertNil(
            window.rootViewController?.presentedViewController,
            "the confirmation is a system alert again; its buttons cannot carry identifiers"
        )
    }

    func testTheRemovalConfirmationIsNotPresentedOverTheSheetEither() throws {
        let model = makeModel(isPreparing: false)
        let window = host(PaymentSheetView(model: model))

        model.cardPendingRemoval = Self.storedCard
        host.settle()

        XCTAssertNil(window.rootViewController?.presentedViewController)
    }

    /// The Done control above the keypad, which lives on a `UIBarButtonItem`
    /// rather than in the view tree.
    func testTheKeypadAccessoryPublishesItsIdentifier() throws {
        let window = hostForm()
        let field = try XCTUnwrap(
            textFields(in: window).first {
                $0.accessibilityIdentifier == PayCrossTestIdentifiers.cvv.rawValue
            }
        )
        let bar = try XCTUnwrap(field.inputAccessoryView as? UIToolbar)
        XCTAssertNotNil(
            bar.items?.first {
                $0.accessibilityIdentifier == PayCrossTestIdentifiers.keyboardDone.rawValue
            },
            "the accessory's Done control is unnamed"
        )
    }

    // MARK: - Hosting

    private static let storedCard = SavedCard(
        id: "6f1c9c3e-0d5a-4a3f-9c2b-4d0e1f2a3b4c",
        brand: .visa, last4: "0366", expiryLabel: "03/29"
    )

    private func makeModel(isPreparing: Bool) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1", brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
            ),
            configuration: Configuration(environment: .sandbox),
            sessionData: isPreparing ? nil : SessionData(),
            isPreparing: isPreparing,
            transport: StubTransport(json: #"{"session_id":"sess_1","status":"open"}"#)
        )
    }

    private func hostForm(showsApplePayButton: Bool = false) -> UIWindow {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            allowsSaving: true,
            isLoading: false,
            fieldGroups: [],
            fieldValues: .constant([:]),
            fieldErrors: [],
            onPay: {},
            showsApplePayButton: showsApplePayButton,
            onApplePay: {}
        )
        return host(NavigationStack { view })
    }

    private func identifiers(in view: UIView) -> Set<String> {
        var found: Set<String> = []
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            found.insert(identifier)
        }
        for subview in view.subviews {
            found.formUnion(identifiers(in: subview))
        }
        return found
    }

}
#endif
