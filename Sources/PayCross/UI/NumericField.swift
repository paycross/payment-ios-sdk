#if os(iOS)
import SwiftUI
import UIKit

// A number pad has no Return key, and inputAccessoryView is the only place for a Done bar, which SwiftUI does not expose.
struct NumericField: UIViewRepresentable {
    @Environment(\.payCrossAppearance) private var style
    let placeholder: String
    @Binding var text: String
    // Without a label UITextField announces its placeholder, so the card number would read its example digits.
    let accessibleName: String
    var isSecure = false
    var contentType: UITextContentType?
    let identifier: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.isSecureTextEntry = isSecure
        field.textContentType = contentType
        // UIKit's own re-scaling ignores the sheet's size clamp, so applyStyle scales the font through UIFontMetrics instead.
        field.adjustsFontForContentSizeCategory = false
        applyStyle(to: field)
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibleName
        field.delegate = context.coordinator
        field.inputAccessoryView = context.coordinator.doneBar
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // A bare UITextField in an HStack collapses to its text, so it needs the priorities below.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        KeypadDismissal.register(field)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        // The heading is localized per sheet install, so the label is set on every render.
        field.accessibilityLabel = accessibleName
        applyStyle(to: field)
        if field.text != text {
            field.text = text
        }
    }

    // SwiftUI's .font and .foregroundStyle do not reach the UIView a representable wraps.
    private func applyStyle(to field: UITextField) {
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedDigitSystemFont(
                ofSize: style.scaledPointSize(17), weight: .regular
            ),
            compatibleWith: style.scaledTraits
        )
        field.textColor = style.uiColor(\.text) ?? .label

        if let placeholderColor = style.uiColor(\.placeholder) {
            field.attributedPlaceholder = NSAttributedString(
                string: placeholder, attributes: [.foregroundColor: placeholderColor]
            )
        } else {
            field.placeholder = placeholder
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        // Weak, since the field owns the accessory bar, which owns this coordinator.
        weak var field: UITextField?

        lazy var doneBar: UIToolbar = {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
            let done = UIBarButtonItem(
                title: L("paycross_keyboard_done", "Done"),
                style: .done,
                target: self,
                action: #selector(dismissKeypad)
            )
            done.accessibilityIdentifier = PayCrossTestIdentifiers.keyboardDone.rawValue
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

        @objc func dismissKeypad() {
            field?.resignFirstResponder()
        }

        // A secure UITextField replaces its whole text on the first edit after it regains focus.
        // Rewriting the text here spends that edit, since shouldChangeCharactersIn is not reached by every input path.
        func textFieldDidBeginEditing(_ field: UITextField) {
            guard field.isSecureTextEntry, let existing = field.text, !existing.isEmpty else {
                return
            }
            field.text = ""
            field.insertText(existing)
        }
    }
}

// Scoped to the SDK's own fields, since endEditing or sendAction to a nil target would reach the host app's views.
@MainActor
enum KeypadDismissal {
    // Weak, so the registry never keeps a dismissed sheet's fields alive.
    private struct Box { weak var field: UITextField? }
    private static var boxes: [Box] = []

    static func register(_ field: UITextField) {
        boxes.removeAll { $0.field == nil || $0.field === field }
        boxes.append(Box(field: field))
    }

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
