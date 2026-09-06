#if os(iOS)
import SwiftUI

/// A confirmation the sheet draws itself, rather than a `.alert`.
///
/// **Measured, not assumed.** SwiftUI renders `.alert` through a
/// `UIAlertController`, and it does not carry a `Button`'s
/// `accessibilityIdentifier` onto the resulting `UIAlertAction`: with the cancel
/// confirmation open on iOS 26.5, both actions answered `accessibilityIdentifier`
/// with nil and the alert's whole view tree carried none. So the four buttons the
/// README promises could not be reached by name, and neither could the two
/// dialogs, which have no view the SDK ever holds.
///
/// Drawn here instead, the six identifiers are ordinary SwiftUI ones, applied the
/// same way as the Pay button's and reachable the same way. That is the whole
/// reason this exists: it is not a nicer alert, it is an addressable one, and it
/// matches the dialog identifiers Android already publishes.
///
/// A title, a message, then the two answers stacked, destructive first and the
/// one that changes nothing under it where the thumb rests. Stacked at every
/// size rather than only at accessibility ones: `Continue Payment` already wraps
/// beside `Yes, Cancel` on a 390pt sheet, and `Continuer le paiement` is longer
/// still. A row that has to be measured before it is safe is a row that breaks
/// in the next language.
struct ConfirmationDialog: View {
    @Environment(\.payCrossAppearance) private var style
    /// Where VoiceOver is put when the question appears. The `.isModal` trait
    /// below keeps it inside; this is what gets it in.
    @AccessibilityFocusState private var titleFocused: Bool

    /// One of the two answers.
    struct Choice {
        let title: String
        let identifier: PayCrossTestIdentifiers
        let action: () -> Void
    }

    let identifier: PayCrossTestIdentifiers
    let title: String
    let message: String
    /// The one that goes through with it. Drawn in the error colour, because
    /// both of these end something the shopper cannot get back.
    let confirm: Choice
    /// The one that leaves everything as it was.
    let dismiss: Choice
    /// Announces the appearance to VoiceOver. Injected only so a test can watch
    /// it happen: focus state is not readable, and there is no VoiceOver in a
    /// test process to read it with.
    var announceAppearance: () -> Void = { SheetAnnouncement.screenChanged() }

    var body: some View {
        ZStack {
            // Opaque enough to read against, and it takes the touches: a tap
            // outside is not an answer, exactly as a system alert has it.
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
            // VoiceOver stays inside the question until it is answered. Without
            // it the form underneath is still read out, and still operable.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .payCrossIdentifier(identifier)
        }
        .onAppear {
            // A question drawn over a raised keypad is a question half off the
            // screen. The alert this replaces put the keypad away on the way up.
            KeypadDismissal.resignFirstResponder()
            // And it moved VoiceOver onto itself. Both halves: the notification
            // tells VoiceOver to re-orient, the focus state says where to land.
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
