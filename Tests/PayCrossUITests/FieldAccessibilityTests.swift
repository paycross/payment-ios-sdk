#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

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

    func testTheSpokenNameIsNeverThePlaceholder() {
        let row = self.row(Self.line1, state: Self.optional, language: "en")
        XCTAssertNotEqual(row.accessibleName, Self.line1.placeholder)
    }

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
            optedInGroups: .constant([]),
            fieldErrors: [],
            language: SheetLanguage.tag,
            onPay: {}
        )
        return host(NavigationStack { view })
    }
}
#endif
