#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// A field the session locks has to look locked.
///
/// The lock itself has always worked — the control is disabled, it refuses the
/// focus, and typing at it leaves its value byte-identical. Only the drawing
/// was missing, so every existing assertion passed while the shopper's only way
/// to discover a locked field was to tap it and watch nothing happen. That is
/// exactly the shape of defect a render comparison catches and a behavioural
/// test cannot: measured on the SDK before this change, a read-only field and
/// an editable one differed by zero pixels.
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

    /// One field, differing from its twin by the lock and nothing else.
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

    /// A locked select. Its empty row has to sit on something, so the rule
    /// there is the dash rather than nothing at all.
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
        // Longer than the shared settle, for the reason the language suite
        // gives: a layer read before the text has drawn compares two blank
        // forms and reports no difference between them.
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private func placeholders(in window: UIWindow) -> [String] {
        textFields(in: window).compactMap { $0.placeholder ?? $0.attributedPlaceholder?.string }
    }

    // MARK: - The two fields no longer draw the same

    /// The issue as filed. Both fields carry the same value, so nothing but the
    /// treatment of the lock can move a pixel.
    func testALockedFieldIsDrawnDifferentlyFromAnEditableOne() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(group(readOnly: true), filled), render(group(readOnly: false), filled)
            ),
            0,
            "a locked field is still the editable box exactly; nothing on screen says it is locked"
        )
    }

    /// The control. Without it a comparison that always differs would look like
    /// a proof.
    func testTwoEditableFieldsDrawIdentically() throws {
        XCTAssertEqual(
            try differingPixels(
                render(group(readOnly: false), filled), render(group(readOnly: false), filled)
            ),
            0,
            "two renders of the same form differ; the comparison above proves nothing"
        )
    }

    /// The worse case found while testing: a locked field with no value drew a
    /// grey example, which reads as a city the merchant filled in rather than
    /// as one to type. There is nothing to type into.
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

    /// A select cannot draw nothing: its empty row is the thing the closed menu
    /// shows. The dash is what an unset select has always sat on.
    func testALockedEmptySelectDrawsTheDashRatherThanItsPlaceholder() throws {
        XCTAssertGreaterThan(
            try differingPixels(render(select(readOnly: true)), render(select(readOnly: false))),
            0,
            "the locked select drew the same empty row as the editable one"
        )
    }

    /// The caret needs no code of its own and never did: a disabled control
    /// takes no first responder, and the row hands it no tap to focus with.
    /// Pinned here because the fix is described as three things, and this is
    /// the one that was already true.
    func testALockedFieldTakesNoInput() {
        let locked = textFields(in: form(group(readOnly: true), filled))
            .filter { !$0.isEnabled }
        XCTAssertEqual(locked.count, 1, "the locked field is not the disabled one")
        XCTAssertFalse(locked[0].becomeFirstResponder(), "a locked field took the caret")
    }

    // MARK: - The colour comes from the appearance system

    /// Derived rather than named. A merchant who themed the component colour
    /// gets a locked box that still belongs to their palette instead of a grey
    /// one dropped into a branded form.
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

    /// And an unthemed sheet mutes by the same rule rather than by a second,
    /// hardcoded colour: the fill being muted is then the platform's own, which
    /// is near-white in one appearance and near-black in the other.
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
