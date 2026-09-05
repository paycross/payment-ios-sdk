#if os(iOS)
import SwiftUI
import UIKit

/// A numeric entry field that carries a Done button above the keypad.
///
/// `UIKeyboardType.numberPad` has no Return key and iOS attaches no accessory of
/// its own, so a SwiftUI `TextField`/`SecureField` on that keyboard offers the
/// shopper nothing that puts the pad away. The only place to hang a control is
/// `inputAccessoryView`, which SwiftUI does not expose, so these three fields are
/// UIKit ones. The alphabetic cardholder-name field keeps its Return key and stays
/// a SwiftUI `TextField`.
///
/// Holds no validation: text goes out through the binding to `CardFormReducer`,
/// exactly as the SwiftUI fields did.
struct NumericField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    let identifier: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.isSecureTextEntry = isSecure
        field.textContentType = contentType
        field.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .regular))
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityIdentifier = identifier
        field.delegate = context.coordinator
        field.inputAccessoryView = context.coordinator.doneBar
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // A bare UITextField in an HStack collapses to its text; these make it
        // take the space the old SwiftUI field took.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        KeypadDismissal.register(field)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        // The binding is captured per render, so the coordinator has to be handed
        // the current one or edits write into a stale view's state.
        context.coordinator.text = $text
        field.placeholder = placeholder
        if field.text != text {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        /// Weak: the field owns the accessory, which owns this.
        weak var field: UITextField?

        /// Built once and shared by the field it is attached to. The identifier is
        /// on the button so the E2E runner that found this bug can press it.
        lazy var doneBar: UIToolbar = {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
            let done = UIBarButtonItem(
                title: L("keyboard_done", "Done"),
                style: .done,
                target: self,
                action: #selector(dismissKeypad)
            )
            done.accessibilityIdentifier = "keyboardDone"
            bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
            bar.sizeToFit()
            return bar
        }()

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        /// Resigns the field this bar belongs to.
        @objc func dismissKeypad() {
            field?.resignFirstResponder()
        }

        /// A secure `UITextField` replaces its whole contents on the first edit
        /// after it regains focus — measured, not assumed: typing "1", leaving the
        /// field, returning and typing "2" leaves "2". A shopper who taps back to
        /// check their expiry would silently lose the digits already entered.
        ///
        /// Rewriting the text here spends that first edit, so the shopper's next
        /// keystroke appends. The obvious place for this, the delegate's
        /// `shouldChangeCharactersIn`, is not reached by every input path.
        func textFieldDidBeginEditing(_ field: UITextField) {
            guard field.isSecureTextEntry, let existing = field.text, !existing.isEmpty else {
                return
            }
            field.text = ""
            field.insertText(existing)
        }
    }
}

/// Puts away the keypad the sheet raised.
///
/// The tap-anywhere gesture holds no reference to any field, so it comes through
/// here. Scoped to the SDK's own fields on purpose: the one-line idioms for this
/// — `endEditing` on every window, or `sendAction` to a nil target — reach into
/// the host app's view hierarchy, which is not this SDK's to close.
@MainActor
enum KeypadDismissal {
    /// The fields the sheet has built. Weak boxes, holding references to the
    /// fields and never to anything typed into them; a dismissed sheet's entries
    /// go nil and are dropped on the next call.
    private struct Box { weak var field: UITextField? }
    private static var boxes: [Box] = []

    static func register(_ field: UITextField) {
        boxes.removeAll { $0.field == nil || $0.field === field }
        boxes.append(Box(field: field))
    }

    /// True when there was a keypad to put away.
    @discardableResult
    static func resignFirstResponder() -> Bool {
        boxes.removeAll { $0.field == nil }
        guard let editing = boxes.compactMap(\.field).first(where: \.isFirstResponder) else {
            return false
        }
        return editing.resignFirstResponder()
    }
}
#endif
