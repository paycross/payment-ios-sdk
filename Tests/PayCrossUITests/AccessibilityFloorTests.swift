#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class AccessibilityFloorTests: XCTestCase {

    private let host = ViewHost()

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - The clamp

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

    func testAStackedFieldTakesTheFullWidth() throws {
        let large = try expiryAndCVV(at: .accessibility3)
        XCTAssertEqual(
            large.expiry.width, large.cvv.width, accuracy: 1,
            "stacked fields must be the same width"
        )
        XCTAssertGreaterThan(large.cvv.width, 200, "the CVV field is still being squeezed")
    }

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

    func testASecondReasonIsAnnouncedToo() throws {
        var spoken: [String] = []
        let messages = MessageBox(value: "Payment failed. Please try again.")
        _ = host(BannerHost(messages: messages) { spoken.append($0) })

        messages.value = "Network error. Please try again."
        host.settle()

        XCTAssertEqual(
            spoken, ["Payment failed. Please try again.", "Network error. Please try again."]
        )
    }

    // MARK: - The confirmations

    func testAConfirmationTellsVoiceOverItAppeared() throws {
        var announced = 0
        _ = host(
            ConfirmationDialog(
                identifier: .cancelDialog,
                title: "Cancel Payment?",
                message: "Are you sure you want to cancel this payment?",
                confirm: .init(title: "Yes, Cancel", identifier: .cancelConfirm) {},
                dismiss: .init(title: "Continue Payment", identifier: .cancelDismiss) {},
                announceAppearance: { announced += 1 }
            )
        )

        XCTAssertEqual(announced, 1)
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
            optedInGroups: .constant([]),
            fieldErrors: [],
            language: SheetLanguage.tag,
            onPay: {}
        )
        return host(view.payCrossTypeScale(.unstyled).dynamicTypeSize(size))
    }


}

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
