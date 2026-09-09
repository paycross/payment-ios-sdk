#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

/// What the sheet's fields are called out loud.
///
/// Every field on this form draws its heading as a separate `Text` above the
/// control, and nothing associated the two: the control's accessible name fell
/// back to its placeholder, so the card number announced its own example digits,
/// the security code announced three bullets, and a merchant field with no
/// example announced nothing at all.
///
/// The three card fields are `UITextField`s the SDK builds itself, so their
/// spoken name is a property this bundle can read back exactly. The cardholder
/// field and the server-driven ones are SwiftUI `TextField`s, and SwiftUI keeps
/// its accessibility tree out of reach here — measured: a hosted `TextField`
/// reports a nil `accessibilityLabel` on the `UITextField` under it however the
/// modifier is applied, and forcing the container protocol open returns no
/// elements without an assistive technology running. What those fields will say
/// is asserted as the string the view computes, and the modifier landing on the
/// control is checked on a simulator against a live session.
@MainActor
final class FieldAccessibilityTests: XCTestCase {

    private let host = ViewHost()

    override func setUp() async throws {
        try await super.setUp()
        SheetLanguage.reset()
    }

    override func tearDown() async throws {
        host.release()
        SheetLanguage.reset()
        try await super.tearDown()
    }

    // MARK: - The card fields, read off the control

    /// An empty dictionary would pass every assertion below by naming nothing,
    /// so the read is proved before it is used.
    func testTheReadItselfWorks() throws {
        XCTAssertEqual(
            spokenNames(in: hostForm()).count, 3,
            "the three UIKit-backed card fields are not on screen; nothing below is measuring them"
        )
    }

    func testTheCardNumberIsSpokenAsItsHeadingNotItsExampleDigits() throws {
        let spoken = spokenNames(in: hostForm())
        XCTAssertEqual(spoken[PayCrossTestIdentifiers.cardNumber.rawValue], "Card Number")
        XCTAssertNotEqual(
            spoken[PayCrossTestIdentifiers.cardNumber.rawValue], "1234 5678 9012 3456",
            "the card number is announcing its placeholder again"
        )
    }

    /// The security code is the worst of the three: its placeholder is bullets,
    /// so the fallback name was punctuation.
    func testTheExpiryAndTheSecurityCodeAreSpokenAsTheirHeadings() throws {
        let spoken = spokenNames(in: hostForm())
        XCTAssertEqual(spoken[PayCrossTestIdentifiers.expiry.rawValue], "MM/YY")
        XCTAssertEqual(spoken[PayCrossTestIdentifiers.cvv.rawValue], "CVV")
    }

    func testTheCardFieldsSpokenNamesFollowTheSheetsLanguage() throws {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        let spoken = spokenNames(in: hostForm())

        XCTAssertEqual(spoken[PayCrossTestIdentifiers.cardNumber.rawValue], "Numéro de carte")
        XCTAssertEqual(spoken[PayCrossTestIdentifiers.expiry.rawValue], "MM/AA")
    }

    // MARK: - The server-driven fields, as the row computes them

    func testARequiredFieldIsDrawnWithAStarAndSpokenWithTheWord() {
        let row = self.row(Self.line1, state: Self.required, language: "en")
        XCTAssertEqual(row.title, "Address line 1 *")
        XCTAssertEqual(row.accessibleName, "Address line 1, required")
    }

    func testAnOptionalFieldIsSpokenAsItsLabelAlone() {
        XCTAssertEqual(
            self.row(Self.line1, state: Self.optional, language: "en").accessibleName,
            "Address line 1"
        )
    }

    /// The bug in the round: this field's placeholder is the example address, and
    /// that string was the whole of its spoken name.
    func testTheSpokenNameIsNeverThePlaceholder() {
        let row = self.row(Self.line1, state: Self.optional, language: "en")
        XCTAssertNotEqual(row.accessibleName, Self.line1.placeholder)
    }

    /// A merchant field the server sent no placeholder for announced nothing
    /// identifying at all, which is how first and last name behaved.
    func testAFieldWithNoPlaceholderIsStillNamed() {
        let name = FieldDefinition(
            name: "first_name",
            label: "First name",
            labels: ["en": "First name", "fr": "Prénom"]
        )
        XCTAssertEqual(
            self.row(name, state: Self.required, language: "en").accessibleName,
            "First name, required"
        )
    }

    /// The word comes out of the sheet's own strings file, so it moves with the
    /// language the merchant's label is read in.
    func testTheWholeSpokenNameIsFrenchOnAFrenchSheet() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            self.row(Self.line1, state: Self.required, language: "fr").accessibleName,
            "Ligne d'adresse 1, obligatoire"
        )
    }

    // MARK: - Fixtures and reads

    private static let line1 = FieldDefinition(
        name: "line1",
        label: "Address line 1",
        labels: ["en": "Address line 1", "fr": "Ligne d'adresse 1"],
        placeholder: "123 Main St",
        placeholders: ["en": "123 Main St", "fr": "123 Main St"]
    )

    private static let optional = FieldState(isVisible: true, isRequired: false, isReadOnly: false)
    private static let required = FieldState(isVisible: true, isRequired: true, isReadOnly: false)

    private func row(
        _ field: FieldDefinition, state: FieldState, language: String
    ) -> FieldRow {
        FieldRow(
            groupKey: "billing",
            field: field,
            language: language,
            state: state,
            value: .constant(""),
            error: nil
        )
    }

    /// Spoken name by test identifier, for the fields that carry one.
    private func spokenNames(in window: UIWindow) -> [String: String] {
        var names: [String: String] = [:]
        for field in textFields(in: window) {
            guard let identifier = field.accessibilityIdentifier,
                  identifier.hasPrefix("paycross."),
                  let label = field.accessibilityLabel else { continue }
            names[identifier] = label
        }
        return names
    }

    private func hostForm() -> UIWindow {
        var state = CardFormState()
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1500, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: false,
            fieldGroups: [],
            fieldValues: .constant([:]),
            fieldErrors: [],
            language: SheetLanguage.tag,
            onPay: {}
        )
        return host(NavigationStack { view })
    }
}
#endif
