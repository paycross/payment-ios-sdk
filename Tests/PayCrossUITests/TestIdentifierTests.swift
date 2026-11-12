#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

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

    func testADottedComponentCollides() {
        XCTAssertEqual(
            PayCrossTestIdentifiers.field(group: "a.b", name: "c"),
            PayCrossTestIdentifiers.field(group: "a", name: "b.c"),
            "a dot is now escaped on iOS; Android must be changed to match"
        )
    }

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

    func testTheSheetsContentIsAContainer() {
        let view = PaymentSheetView(model: makeModel(isPreparing: false))
        XCTAssertTrue(
            String(describing: type(of: view.body)).contains("AccessibilityContainerModifier"),
            "the Pay button is answering to paycross.sheet again, or SwiftUI renamed the "
                + "modifier; see the note at the top of this file"
        )
    }

    // MARK: - The rendered tree

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

    func testTheFlatNamesTheseReplacedAreGone() throws {
        let window = hostForm(showsApplePayButton: true)
        let found = identifiers(in: window)

        for old in ["cardNumber", "expiry", "cvv", "applePayButton"] {
            XCTAssertFalse(found.contains(old), "\(old) is still published")
        }
    }

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
