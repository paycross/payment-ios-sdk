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
@MainActor
final class FieldGroupLanguageTests: XCTestCase {

    private let host = ViewHost()

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    /// A group as the backend sends it today: a map beside every rendered string.
    private let bilingual = FieldGroup(
        key: "billing",
        label: "Billing address",
        labels: ["en": "Billing address", "fr": "Adresse de facturation"],
        fields: [
            FieldDefinition(
                name: "postcode",
                type: "text",
                label: "Postcode",
                labels: ["en": "Postcode", "fr": "Code postal"],
                placeholder: "SW1A 1AA",
                placeholders: ["en": "SW1A 1AA", "fr": "75001"],
                required: true
            )
        ]
    )

    /// The same group as a session minted before the maps existed carries it.
    private let singular = FieldGroup(
        key: "billing",
        label: "Billing address",
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

    private func form(_ group: FieldGroup, language: String) -> UIWindow {
        var state = CardFormState()
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: false,
            fieldGroups: [group],
            fieldValues: .constant([:]),
            fieldErrors: [],
            language: language,
            onPay: {}
        )
        return host(NavigationStack { view })
    }

    /// SwiftUI hands a `TextField`'s title to the `UITextField` under it, which
    /// is the one string on this form a hosted test can read back. The card
    /// fields' own placeholders come with it, so an empty list means the read
    /// stopped working rather than that the field lost its placeholder.
    private func placeholders(in window: UIWindow) -> [String] {
        textFields(in: window).compactMap {
            $0.placeholder ?? $0.attributedPlaceholder?.string
        }
    }

    func testTheReadItselfWorks() {
        XCTAssertTrue(
            placeholders(in: form(bilingual, language: "en")).contains("NAME ON CARD"),
            "no placeholder could be read at all; the assertions below prove nothing"
        )
    }

    func testAFrenchSheetDrawsTheServersFrenchPlaceholder() {
        let drawn = placeholders(in: form(bilingual, language: "fr"))
        XCTAssertTrue(drawn.contains("75001"), "drew \(drawn)")
        XCTAssertFalse(drawn.contains("SW1A 1AA"), "the English placeholder is still on screen")
    }

    func testAnEnglishSheetDrawsTheEnglishOne() {
        let drawn = placeholders(in: form(bilingual, language: "en"))
        XCTAssertTrue(drawn.contains("SW1A 1AA"), "drew \(drawn)")
        XCTAssertFalse(drawn.contains("75001"))
    }

    /// The live sessions that predate the maps must draw exactly what they drew
    /// before, whatever language the sheet resolved.
    func testASessionWithoutTheMapsDrawsTheSingularValue() {
        XCTAssertTrue(
            placeholders(in: form(singular, language: "fr")).contains("SW1A 1AA")
        )
    }

    // MARK: - The labels

    /// The heading and the field label are SwiftUI `Text`, so they are asserted
    /// by rendering. The same group with no maps is the control: that render
    /// must not move, which is what makes a difference in the first one mean the
    /// map rather than anything else the language reaches.
    func testTheLabelsAreDrawnInTheSheetsLanguage() throws {
        XCTAssertGreaterThan(
            try differingPixels(render(bilingual, "en"), render(bilingual, "fr")),
            0,
            "the French sheet drew the same labels as the English one"
        )
        XCTAssertEqual(
            try differingPixels(render(singular, "en"), render(singular, "fr")),
            0,
            "a group with no maps must draw the same in either language"
        )
    }

    private func render(_ group: FieldGroup, _ language: String) -> UIImage {
        let window = form(group, language: language)
        // Longer than the shared settle: a layer read before the text has drawn
        // compares two blank forms and passes the control while failing nothing.
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }
}
#endif
