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

    /// Held for the duration of a test; a released window takes the hierarchy
    /// under test with it.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.removeAll()
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

    private func host(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        windows.append(window)
        return window
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

    private func textFields(in view: UIView) -> [UITextField] {
        (view.subviews.compactMap { $0 as? UITextField })
            + view.subviews.flatMap(textFields(in:))
    }
}
#endif
