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
/// carrying `.accessibilityIdentifier` appears nowhere in the hosted hierarchy.
/// Measured again on 2026-09-07, while fixing the containers below, because the
/// fix would have been worth a rendered-tree test: on a hosted `PaymentSheetView`
/// the whole window carries exactly three identifiers, the three `UITextField`s
/// that set their own, and `accessibilityElements` answers with plain subviews
/// rather than SwiftUI nodes. `UIApplication.shared.connectedScenes` is empty and
/// `_AXSApplicationAccessibilityEnabled()` already answers true, so neither a
/// scene nor the accessibility switch is what is missing. And SwiftUI does not
/// write an inherited identifier down onto a `UIViewRepresentable`'s `UIView`
/// either — a representable leaf under an identified container reports nil — so
/// there is no UIKit-level shadow of the propagation to read.
///
/// The UIKit-backed leaves are a different matter, because their identifier is
/// set on a `UIView` that exists whether anything is reading the accessibility
/// tree or not, and those are asserted below on a real render. For everything
/// SwiftUI draws, what can be asserted here is the composed *type* of the view,
/// which is what the compiler hands SwiftUI to build the tree from.
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

    // MARK: - Containers that keep their children

    /// `payCrossContainerIdentifier` establishes the element boundary *before*
    /// it names it.
    ///
    /// Order is the whole fix. A plain identifier on a container is inherited by
    /// every descendant not already inside an element of its own, and the
    /// container's string wins: 0.7.0 published `paycross.sheet` on the Pay
    /// button and `paycross.savedCards` on all three picker rows, so the
    /// README's own example found nothing. `children: .contain` applied first
    /// makes the container an element, and the identifier lands on it alone.
    /// Applied second it would name the boundary and leave the propagation
    /// where it was.
    ///
    /// The composed type is the assertion because the rendered tree is not
    /// readable here; see the note at the top of this file. `SwiftUI` names
    /// these two modifiers, so a release that renames either fails this test
    /// rather than the sheet — measure it again and rewrite this.
    func testAContainerIdentifierEstablishesItsBoundaryFirst() throws {
        let composed = String(describing: type(of:
            Color.clear.payCrossContainerIdentifier(.savedCards)
        ))
        let boundary = try XCTUnwrap(
            composed.range(of: "AccessibilityContainerModifier"),
            "no element boundary: \(composed)"
        )
        let identifier = try XCTUnwrap(
            composed.range(of: "AccessibilityAttachmentModifier"),
            "no identifier: \(composed)"
        )
        XCTAssertLessThan(
            boundary.lowerBound, identifier.lowerBound,
            "the identifier is applied under the boundary rather than on it: \(composed)"
        )
    }

    /// The picker, which published `paycross.savedCards` on every row.
    func testTheStoredCardPickerIsAContainer() {
        let picker = SavedCardPicker(
            cards: [Self.storedCard],
            selection: .newCard,
            allowsRemoval: true,
            isPaying: false,
            onSelect: { _ in },
            onRemoveRequested: { _ in }
        )
        XCTAssertTrue(
            String(describing: type(of: picker.body)).contains("AccessibilityContainerModifier"),
            "the rows, their bins and Use a new card are answering to paycross.savedCards "
                + "again, or SwiftUI renamed the modifier; see the note at the top of this file"
        )
    }

    /// The sheet's own content, which published `paycross.sheet` on the Pay
    /// button and on the initial spinner.
    func testTheSheetsContentIsAContainer() {
        let view = PaymentSheetView(model: makeModel(isPreparing: false))
        XCTAssertTrue(
            String(describing: type(of: view.body)).contains("AccessibilityContainerModifier"),
            "the Pay button is answering to paycross.sheet again, or SwiftUI renamed the "
                + "modifier; see the note at the top of this file"
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
            optedInGroups: .constant([]),
            fieldErrors: [],
            language: SheetLanguage.tag,
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
