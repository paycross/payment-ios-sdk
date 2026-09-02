#if os(iOS)
import PassKit
import SwiftUI

/// Apple's own button, wrapped for SwiftUI.
///
/// `PKPaymentButton` rather than anything drawn here: Apple's brand guidelines
/// require their control, and an app shipping a lookalike is a review
/// rejection. `.automatic` style so it follows the shopper's appearance
/// setting, which SwiftUI cannot do for a UIKit control any other way.
struct ApplePayButtonView: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        button.cornerRadius = 10
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
#endif
