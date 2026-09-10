#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// A decline the shopper cannot see is a decline that did not happen.
///
/// The banner was the last thing in the scrolling column, below the fields, the
/// field groups and the save toggle, and under the pinned footer. On a form with
/// server-driven field groups it landed off the bottom of the screen: the shopper
/// got a form that looked unchanged, a Pay button that had gone disabled because
/// the CVV was cleared, and no reason for either.
///
/// Asserted by rendering, because that is the only thing that answers the actual
/// question. Nothing in the accessibility tree or the view hierarchy distinguishes
/// "in the layout" from "on the screen", and the banner was always the former.
@MainActor
final class DeclineBannerTests: XCTestCase {

    private static let size = CGSize(width: 390, height: 844) // iPhone 17 portrait

    /// Held for the duration of the test; a released window takes the hierarchy
    /// under test with it.
    private var windows: [UIWindow] = []

    /// Enough server-driven fields to push the column past one screen, which is
    /// the condition the bug was found under.
    private func fieldGroups(_ count: Int) -> [FieldGroup] {
        (0..<count).map { index in
            FieldGroup(
                key: "g\(index)",
                label: "Group \(index)",
                fields: [FieldDefinition(name: "f\(index)", label: "Field \(index)", required: true)]
            )
        }
    }

    private func render(declineMessage: String?, fieldGroupCount: Int) -> UIImage {
        var state = CardFormState()
        if let declineMessage {
            CardFormReducer.reduce(state: &state, event: .declined(message: declineMessage))
        }

        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            allowsSaving: true,
            isLoading: false,
            fieldGroups: fieldGroups(fieldGroupCount),
            fieldValues: .constant([:]),
            optedInGroups: .constant([]),
            fieldErrors: [],
            language: SheetLanguage.tag,
            onPay: {}
        )

        let controller = UIHostingController(rootView: NavigationStack { view })
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // Let SwiftUI commit its layout before the layer tree is read.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        windows.append(window)

        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    /// The regression itself. With eight field groups the banner used to change
    /// nothing at all on screen — exactly zero pixels.
    func testADeclineIsVisibleOnAFormTallerThanTheScreen() throws {
        let plain = render(declineMessage: nil, fieldGroupCount: 8)
        let declined = render(
            declineMessage: "Payment failed. Please try again.",
            fieldGroupCount: 8
        )

        XCTAssertGreaterThan(
            try differingPixels(plain, declined), 0,
            "a shopper on a long form saw an unchanged screen and a disabled Pay button"
        )
    }

    func testADeclineIsVisibleOnAShortForm() throws {
        let plain = render(declineMessage: nil, fieldGroupCount: 0)
        let declined = render(
            declineMessage: "Payment failed. Please try again.",
            fieldGroupCount: 0
        )

        XCTAssertGreaterThan(try differingPixels(plain, declined), 0)
    }
}
#endif
