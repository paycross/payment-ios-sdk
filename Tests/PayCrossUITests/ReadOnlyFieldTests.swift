#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class ReadOnlyFieldTests: XCTestCase {

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

    private func group(readOnly: Bool) -> FieldGroup {
        FieldGroup(
            key: "billing",
            fields: [
                FieldDefinition(
                    name: "city",
                    type: "text",
                    label: "City",
                    placeholder: "CITY EXAMPLE",
                    readonly: readOnly
                )
            ]
        )
    }

    private func select(readOnly: Bool) -> FieldGroup {
        FieldGroup(
            key: "billing",
            fields: [
                FieldDefinition(
                    name: "country",
                    type: "select",
                    label: "Country",
                    placeholder: "Select a country...",
                    readonly: readOnly,
                    options: [FieldOption(value: "US", label: "United States")]
                )
            ]
        )
    }

    private let filled = ["billing": ["city": "New York"]]

    private func form(_ group: FieldGroup, _ values: [String: [String: String]]) -> UIWindow {
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
            language: "en",
            onPay: {}
        )
        return host(NavigationStack { view })
    }

    private func render(
        _ group: FieldGroup, _ values: [String: [String: String]] = [:]
    ) -> UIImage {
        let window = form(group, values)
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private func placeholders(in window: UIWindow) -> [String] {
        textFields(in: window).compactMap { $0.placeholder ?? $0.attributedPlaceholder?.string }
    }

    // MARK: - The two fields no longer draw the same

    func testALockedFieldIsDrawnDifferentlyFromAnEditableOne() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(group(readOnly: true), filled), render(group(readOnly: false), filled)
            ),
            0,
            "a locked field is still the editable box exactly; nothing on screen says it is locked"
        )
    }

    func testTwoEditableFieldsDrawIdentically() throws {
        XCTAssertEqual(
            try differingPixels(
                render(group(readOnly: false), filled), render(group(readOnly: false), filled)
            ),
            0,
            "two renders of the same form differ; the comparison above proves nothing"
        )
    }

    func testALockedEmptyFieldDrawsNoPlaceholder() {
        XCTAssertFalse(
            placeholders(in: form(group(readOnly: true), [:])).contains("CITY EXAMPLE"),
            "the locked field is still offering an example of what to type"
        )
    }

    func testAnEditableEmptyFieldStillDrawsItsPlaceholder() {
        XCTAssertTrue(
            placeholders(in: form(group(readOnly: false), [:])).contains("CITY EXAMPLE"),
            "the placeholder was dropped from every field, not only the locked one"
        )
    }

    func testALockedEmptySelectDrawsTheDashRatherThanItsPlaceholder() throws {
        XCTAssertGreaterThan(
            try differingPixels(render(select(readOnly: true)), render(select(readOnly: false))),
            0,
            "the locked select drew the same empty row as the editable one"
        )
    }

    func testALockedFieldDrawsItsTextInTheSupportingColour() throws {
        let locked = try XCTUnwrap(textFields(in: form(group(readOnly: true), filled)).last)
        let editable = try XCTUnwrap(textFields(in: form(group(readOnly: false), filled)).last)
        XCTAssertFalse(locked.isEnabled, "the last field on the form is not the locked one")
        XCTAssertTrue(editable.isEnabled)
        XCTAssertNotEqual(
            locked.textColor?.payCrossColor, editable.textColor?.payCrossColor,
            "a locked field draws its text in the same colour an editable one does"
        )
    }

    func testALockedFieldTakesNoInput() {
        let locked = textFields(in: form(group(readOnly: true), filled))
            .filter { !$0.isEnabled }
        XCTAssertEqual(locked.count, 1, "the locked field is not the disabled one")
        XCTAssertFalse(locked[0].becomeFirstResponder(), "a locked field took the caret")
    }

    // MARK: - The colour comes from the appearance system

    func testTheLockedFillIsDerivedFromTheMerchantsOwnComponentColour() {
        let brandComponent = PayCrossColor(red: 0x1E, green: 0x88, blue: 0xE5)
        let style = AppearanceStyle(resolved: AppearanceResolver.resolve(
            appearance: PayCrossAppearance(
                light: PayCrossColors(component: brandComponent),
                dark: PayCrossColors(component: brandComponent)
            )
        ))
        let light = UITraitCollection(userInterfaceStyle: .light)
        let locked = UIColor(style.readOnlyComponent).resolvedColor(with: light)
        let editable = UIColor(style.color(\.component) ?? .clear).resolvedColor(with: light)

        XCTAssertNotEqual(locked.payCrossColor, editable.payCrossColor)
        XCTAssertEqual(locked.payCrossColor, AppearanceResolver.muted(brandComponent))
    }

    func testAnUnthemedSheetMutesThePlatformsOwnFillInBothAppearances() {
        let locked = UIColor(AppearanceStyle.unstyled.readOnlyComponent)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let base = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            XCTAssertNotEqual(
                locked.resolvedColor(with: traits).payCrossColor, base.payCrossColor,
                "the locked box is the editable box's own fill in \(style == .light ? "light" : "dark")"
            )
        }
    }
}
#endif
