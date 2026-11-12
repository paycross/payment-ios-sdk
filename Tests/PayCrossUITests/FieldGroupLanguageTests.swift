#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class FieldGroupLanguageTests: XCTestCase {

    private let host = ViewHost()

    override func setUp() async throws {
        try await super.setUp()
        SheetLanguage.reset()
    }

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - Fixtures

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
            optedInGroups: .constant([]),
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

    func testASessionWithoutTheMapsDrawsTheSingularValue() {
        XCTAssertTrue(
            placeholders(in: form(placeholderGroupSingular, language: "fr")).contains("SW1A 1AA")
        )
    }

    // MARK: - Labels, by rendering

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

    // MARK: - The empty row of a select

    private let selectWithPlaceholder = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "country",
                type: "select",
                label: "Country",
                placeholder: "Select a country...",
                placeholders: [
                    "en": "Select a country...", "fr": "Sélectionnez un pays..."
                ],
                options: [FieldOption(value: "US", label: "United States")]
            )
        ]
    )

    private let selectWithoutPlaceholder = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "country",
                type: "select",
                label: "Country",
                options: [FieldOption(value: "US", label: "United States")]
            )
        ]
    )

    private let selectWithDashPlaceholder = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "country",
                type: "select",
                label: "Country",
                placeholder: "—",
                options: [FieldOption(value: "US", label: "United States")]
            )
        ]
    )

    private let selectWithEmptyPlaceholder = FieldGroup(
        key: "billing",
        fields: [
            FieldDefinition(
                name: "country",
                type: "select",
                label: "Country",
                placeholder: "",
                placeholders: ["en": "", "fr": ""],
                options: [FieldOption(value: "US", label: "United States")]
            )
        ]
    )

    private let chosenCountry = ["billing": ["country": "US"]]

    func testAnUnsetSelectDrawsThePlaceholderInTheSheetsLanguage() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(selectWithPlaceholder, "en"), render(selectWithPlaceholder, "fr")
            ),
            0,
            "the French sheet drew the same empty row as the English one"
        )
    }

    func testAnUnsetSelectDrawsThePlaceholderRatherThanTheDash() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(selectWithPlaceholder, "en"), render(selectWithoutPlaceholder, "en")
            ),
            0,
            "the select ignored the placeholder the session sent for it"
        )
    }

    func testASelectWithNoPlaceholderStillDrawsTheDash() throws {
        XCTAssertEqual(
            try differingPixels(
                render(selectWithoutPlaceholder, "en"), render(selectWithDashPlaceholder, "en")
            ),
            0,
            "an unset select with no placeholder no longer draws the em dash"
        )
    }

    func testASelectWhosePlaceholderIsEmptyDrawsTheDash() throws {
        XCTAssertEqual(
            try differingPixels(
                render(selectWithEmptyPlaceholder, "en"), render(selectWithoutPlaceholder, "en")
            ),
            0,
            "an empty placeholder drew a blank empty row instead of the em dash"
        )
    }

    func testAChosenOptionIsDrawnWhicheverPlaceholderTheFieldCarries() throws {
        XCTAssertEqual(
            try differingPixels(
                render(selectWithPlaceholder, "en", chosenCountry),
                render(selectWithoutPlaceholder, "en", chosenCountry)
            ),
            0,
            "the placeholder is leaking into a select that has a value"
        )
    }

    private func render(
        _ group: FieldGroup,
        _ language: String,
        _ values: [String: [String: String]] = [:]
    ) -> UIImage {
        let window = form(group, language: language, values: values)
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }
}
#endif
