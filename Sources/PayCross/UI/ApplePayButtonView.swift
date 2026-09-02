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

    /// False while a payment is being submitted.
    ///
    /// Set on the control itself, because SwiftUI's `.disabled()` does not
    /// reach the `UIView` a `UIViewRepresentable` wraps. Without it the primary
    /// action of the whole feature stays fully lit for the submit and poll
    /// phase, which can run for minutes, doing nothing when tapped -- while the
    /// spinner sits on the card button, the one control the shopper is not
    /// looking at.
    var isEnabled: Bool = true

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        button.cornerRadius = 10
        // On the control as well as on the SwiftUI node, which is where the
        // modifier in CardFormView puts it. Anything walking UIViews -- a UI
        // test, the demo harness -- finds nothing otherwise.
        button.accessibilityIdentifier = "applePayButton"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
        // `isUserInteractionEnabled`, not `isEnabled` alone: PKPaymentButton
        // ignores `isEnabled` and reports true however it is set -- measured on
        // iOS 26.5, where the alpha took effect on the same view and the
        // enabled flag did not. Both are set anyway, so the control is right if
        // Apple ever starts honouring it.
        uiView.isEnabled = isEnabled
        uiView.isUserInteractionEnabled = isEnabled
        uiView.alpha = isEnabled ? 1 : 0.4
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    /// `NSObject`, not a bare Swift class.
    ///
    /// `addTarget(_:action:for:)` is Objective-C target-action, and UIKit hands
    /// the registered targets back through `allTargets`, whose elements bridge
    /// as `NSObject`. A Swift-native coordinator registers without complaint
    /// and then traps the moment anything reads that set -- which the
    /// presentation test does, to prove a tap has somewhere to go. Inheriting
    /// from `NSObject` is what this API has always expected of a target.
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
#endif
