#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class DeclineBannerTests: XCTestCase {

    private static let size = CGSize(width: 390, height: 844)

    private var windows: [UIWindow] = []

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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        windows.append(window)

        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

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
