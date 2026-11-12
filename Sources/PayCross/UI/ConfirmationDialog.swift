#if os(iOS)
import SwiftUI

// A SwiftUI .alert does not carry accessibilityIdentifier onto its buttons, so the dialog is drawn here.
// The answers stack at every size, since longer translations do not fit side by side on a 390pt sheet.
struct ConfirmationDialog: View {
    @Environment(\.payCrossAppearance) private var style
    @AccessibilityFocusState private var titleFocused: Bool

    struct Choice {
        let title: String
        let identifier: PayCrossTestIdentifiers
        let action: () -> Void
    }

    let identifier: PayCrossTestIdentifiers
    let title: String
    let message: String
    let confirm: Choice
    let dismiss: Choice
    var announceAppearance: () -> Void = { SheetAnnouncement.screenChanged() }

    var body: some View {
        ZStack {
            // The scrim takes the touches, so a tap outside is not an answer.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(style.font(.headline))
                        .multilineTextAlignment(.center)
                        .accessibilityFocused($titleFocused)
                    Text(message)
                        .font(style.font(.footnote))
                        .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                        .multilineTextAlignment(.center)
                }
                .padding(20)

                Divider()

                button(confirm, isDestructive: true)
                Divider()
                button(dismiss, isDestructive: false)
            }
            .frame(maxWidth: 320)
            .background(
                style.color(\.surface) ?? Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: style.cornerRadius(or: 14))
            )
            .payCrossForeground(style.color(\.text))
            .padding(24)
            // VoiceOver stays inside the question; without this it reads and operates the form underneath.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .payCrossIdentifier(identifier)
        }
        .onAppear {
            // The dialog resigns the keypad, since a raised keypad would leave the question half off screen.
            KeypadDismissal.resignFirstResponder()
            announceAppearance()
            titleFocused = true
        }
    }

    private func button(_ choice: Choice, isDestructive: Bool) -> some View {
        Button(action: choice.action) {
            Text(choice.title)
                .font(style.font(.body, weight: isDestructive ? .regular : .semibold))
                .foregroundStyle(
                    isDestructive
                        ? AnyShapeStyle(style.color(\.error) ?? Color(.systemRed))
                        : style.foreground(\.brand, default: Color.accentColor)
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .payCrossIdentifier(choice.identifier)
    }
}
#endif
