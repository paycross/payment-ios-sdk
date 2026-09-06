#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

/// The accessibility floor, on real renders.
///
/// Every item here is geometry or a side effect, which is why it is asserted at
/// this level rather than in Core: the clamp is a number that has to reach a
/// `UIFont`, the stack is two fields that have to end up above one another, and
/// the announcement is a call that has to happen when a banner appears.
@MainActor
final class AccessibilityFloorTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.removeAll()
        SheetAnnouncement.post = Self.realAnnouncement
        try await super.tearDown()
    }

    private static let realAnnouncement = SheetAnnouncement.post

    // MARK: - The clamp

    /// A merchant's factor multiplies a size that has already been clamped, so
    /// the product cannot walk past the ceiling either.
    func testTheMerchantFactorMultipliesAClampedSize() {
        let style = Self.scaledStyle(1.3)

        let atCeiling = style.withTypeSize(.accessibility3).font(.body)
        for beyond: TypeSizeStep in [.accessibility4, .accessibility5] {
            XCTAssertEqual(
                style.withTypeSize(beyond).font(.body), atCeiling,
                "a themed sheet grows past the ceiling at \(beyond)"
            )
        }
    }

    /// And below the ceiling it still tracks the shopper's setting, which is the
    /// half a clamp is easy to break.
    func testTheMerchantFactorStillTracksSizesUnderTheCeiling() {
        let style = Self.scaledStyle(1.3)
        XCTAssertNotEqual(
            style.withTypeSize(.large).font(.body),
            style.withTypeSize(.accessibility3).font(.body)
        )
    }

    func testTheTraitsAUIKitFontResolvesAgainstAreClamped() {
        XCTAssertEqual(
            Self.scaledStyle(1.3).withTypeSize(.accessibility5)
                .scaledTraits.preferredContentSizeCategory,
            .accessibilityExtraLarge
        )
        XCTAssertEqual(
            Self.scaledStyle(1.3).withTypeSize(.xSmall)
                .scaledTraits.preferredContentSizeCategory,
            .extraSmall
        )
    }

    /// The clamp reaching the appearance through the modifier the sheet applies,
    /// rather than only through a value a test built by hand.
    func testTheSheetsClampReachesTheAppearanceItsViewsRead() throws {
        let seen = TypeSizeSpy()
        _ = host(
            TypeSizeProbe(spy: seen)
                .payCrossTypeScale(.unstyled)
                .dynamicTypeSize(.accessibility5)
        )
        XCTAssertEqual(seen.step, .accessibility3, "the sheet root does not clamp")

        let under = TypeSizeSpy()
        _ = host(
            TypeSizeProbe(spy: under)
                .payCrossTypeScale(.unstyled)
                .dynamicTypeSize(.xxLarge)
        )
        XCTAssertEqual(under.step, .xxLarge, "the clamp is overriding a size under the ceiling")
    }

    // MARK: - Layout

    /// The expiry and the CVV sit side by side at ordinary sizes and stack at
    /// accessibility ones. Measured on the two fields themselves, because the
    /// bug this replaces was them staying side by side and going to slivers.
    func testTheExpiryAndTheCVVStackAtAccessibilitySizes() throws {
        let ordinary = try expiryAndCVV(at: .xxLarge)
        XCTAssertEqual(
            ordinary.expiry.minY, ordinary.cvv.minY, accuracy: 1,
            "the two fields must share a row at ordinary sizes"
        )

        let large = try expiryAndCVV(at: .accessibility3)
        XCTAssertGreaterThan(
            large.cvv.minY, large.expiry.maxY,
            "at an accessibility size the CVV must sit below the expiry, not beside it"
        )
        XCTAssertEqual(
            large.expiry.minX, large.cvv.minX, accuracy: 1,
            "stacked fields must share a left edge"
        )
    }

    /// A stacked CVV is a usable width rather than the sliver the squeeze
    /// produced: both fields take the column.
    func testAStackedFieldTakesTheFullWidth() throws {
        let large = try expiryAndCVV(at: .accessibility3)
        XCTAssertEqual(
            large.expiry.width, large.cvv.width, accuracy: 1,
            "stacked fields must be the same width"
        )
        XCTAssertGreaterThan(large.cvv.width, 200, "the CVV field is still being squeezed")
    }

    /// Apple's 44pt minimum, on the three fields whose control is a `UIView`
    /// this test can measure.
    ///
    /// It caught the defect it now guards: 12pt of padding around a one-line
    /// `UITextField` drew a 46pt box whose tappable half was 22pt. A
    /// `UIViewRepresentable` fills the frame it is given, so a minimum height
    /// on the field is the whole fix for these three.
    ///
    /// The cardholder name and the server-driven fields are SwiftUI
    /// `TextField`s, which centre a one-line control inside the frame instead
    /// of filling it. Measuring their `UITextField` reports 22pt however large
    /// the box is, so the floor there is held by the box claiming the tap and
    /// handing on the focus, which no unit test can press.
    func testEveryUIKitBackedFieldIsATouchTarget() throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let window = hostForm(at: size, fieldGroups: Self.billingGroup)
            let measurable = textFields(in: window).filter {
                $0.accessibilityIdentifier?.hasPrefix("paycross.") == true
            }
            XCTAssertEqual(measurable.count, 3, "the card fields are not all on screen")

            for field in measurable {
                let height = field.convert(field.bounds, to: window).height
                XCTAssertGreaterThanOrEqual(
                    height, 44,
                    "\(field.accessibilityIdentifier ?? "a field") is \(height)pt tall at \(size)"
                )
            }
        }
    }

    // MARK: - The announcement

    func testTheErrorBannerAnnouncesItselfWhenItAppears() throws {
        var spoken: [String] = []
        _ = host(ErrorBanner(message: "Payment failed. Please try again.") { spoken.append($0) })

        XCTAssertEqual(spoken, ["Payment failed. Please try again."])
    }

    /// A second decline with a different reason reuses the view, so appearing is
    /// not the only moment worth speaking.
    func testASecondReasonIsAnnouncedToo() throws {
        var spoken: [String] = []
        let messages = MessageBox(value: "Payment failed. Please try again.")
        _ = host(BannerHost(messages: messages) { spoken.append($0) })

        messages.value = "Network error. Please try again."
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(
            spoken, ["Payment failed. Please try again.", "Network error. Please try again."]
        )
    }

    // MARK: - Helpers

    private static func scaledStyle(_ factor: Double) -> AppearanceStyle {
        AppearanceStyle(
            resolved: AppearanceResolver.resolve(
                appearance: PayCrossAppearance(typography: PayCrossTypography(sizeScaleFactor: factor))
            )
        )
    }

    private func expiryAndCVV(at size: DynamicTypeSize) throws -> (expiry: CGRect, cvv: CGRect) {
        let window = hostForm(at: size)
        let fields = textFields(in: window)
        let expiry = try XCTUnwrap(
            fields.first { $0.accessibilityIdentifier == PayCrossTestIdentifiers.expiry.rawValue },
            "no expiry field"
        )
        let cvv = try XCTUnwrap(
            fields.first { $0.accessibilityIdentifier == PayCrossTestIdentifiers.cvv.rawValue },
            "no CVV field"
        )
        return (
            expiry.convert(expiry.bounds, to: window),
            cvv.convert(cvv.bounds, to: window)
        )
    }

    private static let billingGroup = [FieldGroup(
        key: "billing", label: "Billing address",
        fields: [FieldDefinition(name: "postcode", type: "text", label: "Postcode")]
    )]

    private func hostForm(
        at size: DynamicTypeSize, fieldGroups: [FieldGroup] = []
    ) -> UIWindow {
        var state = CardFormState()
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
            allowsSaving: true,
            isLoading: false,
            fieldGroups: fieldGroups,
            fieldValues: .constant([:]),
            fieldErrors: [],
            onPay: {}
        )
        return host(view.payCrossTypeScale(.unstyled).dynamicTypeSize(size))
    }

    private func host(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        windows.append(window)
        return window
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view.subviews.compactMap { $0 as? UITextField })
            + view.subviews.flatMap(textFields(in:))
    }

}

/// Records what the appearance reported, from inside the tree that set it.
@MainActor
private final class TypeSizeSpy {
    var step: TypeSizeStep?
}

private struct TypeSizeProbe: View {
    @Environment(\.payCrossAppearance) private var style
    let spy: TypeSizeSpy

    var body: some View {
        Color.clear.onAppear { spy.step = style.typeSize }
    }
}

@MainActor
private final class MessageBox: ObservableObject {
    @Published var value: String
    init(value: String) { self.value = value }
}

private struct BannerHost: View {
    @ObservedObject var messages: MessageBox
    let announce: (String) -> Void

    var body: some View {
        ErrorBanner(message: messages.value, announce: announce)
    }
}
#endif
