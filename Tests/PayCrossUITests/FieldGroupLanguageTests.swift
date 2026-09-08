#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// The words on a server-driven field are the server's, not ours.
///
/// Every other string on the sheet is looked up in our bundle by `L`, so a
/// French sheet gets French labels for free. A field group's heading, its
/// fields' labels and placeholders and its options' labels are rendered by the
/// backend, which now sends each of them in every language it renders. Nothing
/// in Core can prove the sheet reaches for the right one, because the tag comes
/// from `SheetLanguage` and the reading is done by the view.
///
/// Each fixture below carries **one** kind of per-language string and nothing
/// else, so a render that moves can only have moved for the reason the test is
/// named after. The paired fixture with no maps at all is the control: with the
/// language as the only differing input, that pair must be pixel-identical.
@MainActor
final class FieldGroupLanguageTests: XCTestCase {

    private let host = ViewHost()

    /// The whole bundle shares one process and one `SheetLanguage`, so the
    /// English chrome these renders draw around the fields is only English if
    /// whatever ran before put the language back. This suite does not depend on
    /// that.
    override func setUp() async throws {
        try await super.setUp()
        SheetLanguage.reset()
    }

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Placeholders only. A placeholder reaches the `UITextField` under a
    /// SwiftUI `TextField`, which is the one drawn string this bundle can read
    /// back exactly.
    private let placeholderGroup = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "postcode",
                type: "text",
                label: "Postcode",
                placeholder: "SW1A 1AA",
                placeholders: ["en": "SW1A 1AA", "fr": "75001"],
                required: true
            )
        ]
    )

    /// The same field as a session minted before the maps carries it.
    private let placeholderGroupSingular = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "postcode",
                type: "text",
                label: "Postcode",
                placeholder: "SW1A 1AA",
                required: true
            )
        ]
    )

    /// The heading and the field label, and no placeholder at all: a placeholder
    /// is drawn by a different line than the labels are, and one that differed
    /// by language would satisfy the comparison on its own.
    private let labelGroup = FieldGroup(
        key: "billing",
        label: "Billing address",
        labels: ["en": "Billing address", "fr": "Adresse de facturation"],
        fields: [
            FieldDefinition(
                name: "postcode",
                type: "text",
                label: "Postcode",
                labels: ["en": "Postcode", "fr": "Code postal"],
                required: true
            )
        ]
    )

    private let labelGroupSingular = FieldGroup(
        key: "billing",
        label: "Billing address",
        fields: [
            FieldDefinition(name: "postcode", type: "text", label: "Postcode", required: true)
        ]
    )

    /// One select option. The field's own label is the same string in both
    /// languages and carries no map, so the option's label is the only thing on
    /// the form that can move.
    private let optionGroup = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "state",
                type: "select",
                label: "State",
                options: [
                    FieldOption(
                        value: "NY",
                        label: "New York",
                        labels: ["en": "New York", "fr": "État de New York"]
                    )
                ]
            )
        ]
    )

    private let optionGroupSingular = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "state",
                type: "select",
                label: "State",
                options: [FieldOption(value: "NY", label: "New York")]
            )
        ]
    )

    /// The option has to be the chosen one before a menu picker draws its label;
    /// an unset select draws the empty tag instead.
    private let chosenOption = ["billing": ["state": "NY"]]

    private func form(
        _ group: FieldGroup,
        language: String,
        values: [String: [String: String]] = [:]
    ) -> UIWindow {
        var state = CardFormState()
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: false,
            fieldGroups: [group],
            fieldValues: .constant(values),
            fieldErrors: [],
            language: language,
            onPay: {}
        )
        return host(NavigationStack { view })
    }

    // MARK: - Placeholders, read back off the control

    private func placeholders(in window: UIWindow) -> [String] {
        textFields(in: window).compactMap {
            $0.placeholder ?? $0.attributedPlaceholder?.string
        }
    }

    /// The card fields' own placeholders come back with the group's, so an empty
    /// list means the read stopped working rather than that a field lost its
    /// placeholder.
    func testTheReadItselfWorks() {
        XCTAssertTrue(
            placeholders(in: form(placeholderGroup, language: "en")).contains("NAME ON CARD"),
            "no placeholder could be read at all; the assertions below prove nothing"
        )
    }

    func testAFrenchSheetDrawsTheServersFrenchPlaceholder() {
        let drawn = placeholders(in: form(placeholderGroup, language: "fr"))
        XCTAssertTrue(drawn.contains("75001"), "drew \(drawn)")
        XCTAssertFalse(drawn.contains("SW1A 1AA"), "the English placeholder is still on screen")
    }

    func testAnEnglishSheetDrawsTheEnglishOne() {
        let drawn = placeholders(in: form(placeholderGroup, language: "en"))
        XCTAssertTrue(drawn.contains("SW1A 1AA"), "drew \(drawn)")
        XCTAssertFalse(drawn.contains("75001"))
    }

    /// The live sessions that predate the maps must draw exactly what they drew
    /// before, whatever language the sheet resolved.
    func testASessionWithoutTheMapsDrawsTheSingularValue() {
        XCTAssertTrue(
            placeholders(in: form(placeholderGroupSingular, language: "fr")).contains("SW1A 1AA")
        )
    }

    // MARK: - Labels, by rendering

    /// A heading, a field label and an option label are SwiftUI `Text`: drawn
    /// into layers rather than into `UILabel`s, and this bundle has no app host
    /// to build an accessibility tree from. So they are asserted by comparing
    /// two renders of a fixture that carries nothing else per-language.
    func testTheHeadingAndTheFieldLabelAreDrawnInTheSheetsLanguage() throws {
        XCTAssertGreaterThan(
            try differingPixels(render(labelGroup, "en"), render(labelGroup, "fr")),
            0,
            "the French sheet drew the same heading and label as the English one"
        )
    }

    func testAGroupWithNoLabelMapsDrawsTheSameInEitherLanguage() throws {
        XCTAssertEqual(
            try differingPixels(
                render(labelGroupSingular, "en"), render(labelGroupSingular, "fr")
            ),
            0
        )
    }

    func testASelectOptionIsDrawnInTheSheetsLanguage() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(optionGroup, "en", chosenOption),
                render(optionGroup, "fr", chosenOption)
            ),
            0,
            "the picker drew the same option label in both languages"
        )
    }

    func testAnOptionWithNoLabelMapDrawsTheSameInEitherLanguage() throws {
        XCTAssertEqual(
            try differingPixels(
                render(optionGroupSingular, "en", chosenOption),
                render(optionGroupSingular, "fr", chosenOption)
            ),
            0
        )
    }

    private func render(
        _ group: FieldGroup,
        _ language: String,
        _ values: [String: [String: String]] = [:]
    ) -> UIImage {
        let window = form(group, language: language, values: values)
        // Longer than the shared settle: a layer read before the text has drawn
        // compares two blank forms and passes the control while failing nothing.
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }
}
#endif
