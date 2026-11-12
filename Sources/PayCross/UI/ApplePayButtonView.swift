#if os(iOS)
import PassKit
import SwiftUI

// Apple's brand guidelines require its own control, so PKPaymentButton is wrapped rather than drawn.
struct ApplePayButtonView: UIViewRepresentable {
    @Environment(\.payCrossAppearance) private var style
    let action: () -> Void

    // SwiftUI's `.disabled()` does not reach the UIView a UIViewRepresentable wraps, so the control is disabled directly.
    var isEnabled: Bool = true

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        // Apple's guidelines own the colours, label and type, so only the corner radius is set.
        button.cornerRadius = style.buttonCornerRadius(or: 10)
        // UI tests walk UIViews, so the identifier is set on the control as well as on the SwiftUI node.
        button.accessibilityIdentifier = PayCrossTestIdentifiers.walletButton.rawValue
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
        // PKPaymentButton ignores `isEnabled`, so `isUserInteractionEnabled` is set as well.
        uiView.cornerRadius = style.buttonCornerRadius(or: 10)
        uiView.isEnabled = isEnabled
        uiView.isUserInteractionEnabled = isEnabled
        uiView.alpha = isEnabled ? 1 : 0.4
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    // UIKit reads targets back as NSObject, so the coordinator inherits NSObject.
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
#endif
