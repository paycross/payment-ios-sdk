#if os(iOS)
import SwiftUI
import PayCrossCore

/// Renders the server-driven field groups.
///
/// Every decision about whether a field shows, is required, or is submitted lives
/// in `FieldGroupLogic` in Core. This file only draws what that logic decides,
/// which is why the conditional-display rules are asserted on Linux.
struct FieldGroupsView: View {
    @Environment(\.payCrossAppearance) private var style
    let groups: [FieldGroup]
    @Binding var values: [String: [String: String]]
    /// Which opt-in groups the shopper has ticked.
    ///
    /// Held by the sheet rather than here, because the same set decides three
    /// things and this view answers only one of them: what is drawn, what is
    /// validated when Pay is pressed, and what goes on the wire.
    @Binding var optedInGroups: Set<String>
    let errors: [FieldGroupError]
    /// The language the sheet resolved, handed down rather than read from
    /// `SheetLanguage` here: the strings on this form come off the wire, and the
    /// tag that picks them must be the one the rest of the chrome already speaks.
    let language: String

    var body: some View {
        ForEach(groups, id: \.key) { group in
            let groupValues = values[group.key] ?? [:]
            // A group the shopper has declined draws no fields at all, which is
            // the same answer Core gives the validation and the submission.
            let visible = FieldGroupLogic.isActive(group, optedIn: optedInGroups)
                ? (group.fields ?? []).filter {
                    FieldGroupLogic.fieldState(for: $0, groupValues: groupValues).isVisible
                }
                : []

            // An opt-in group is on screen even with nothing drawn under it:
            // its toggle is the whole point, and a shopper who cannot see the
            // offer cannot take it.
            if group.isOptIn || !visible.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if group.isOptIn {
                        // The toggle carries the group's own heading, so the
                        // heading is not drawn again above it. A switch and a
                        // title saying the same words are one thing to read,
                        // not two.
                        Toggle(optInCaption(group), isOn: optInBinding(group.key))
                            .font(style.font(.subheadline, weight: .semibold))
                            .accessibilityIdentifier(
                                PayCrossTestIdentifiers.groupOptIn(group: group.key)
                            )
                    } else if let label = group.label(in: language), !label.isEmpty {
                        Text(label)
                            .font(style.font(.subheadline, weight: .semibold))
                    }

                    ForEach(visible, id: \.name) { field in
                        let state = FieldGroupLogic.fieldState(
                            for: field, groupValues: groupValues
                        )
                        FieldRow(
                            groupKey: group.key,
                            field: field,
                            language: language,
                            state: state,
                            value: binding(group: group.key, field: field.name),
                            error: error(group: group.key, field: field.name)
                        )
                    }
                }
            }
        }
    }

    /// What the toggle offering a group is called.
    ///
    /// The group's own heading, in the sheet's language. The merchant already
    /// wrote "Shipping address" there and the backend already translates it; an
    /// SDK string would be a second name for the same group, in our words
    /// rather than theirs, and would stop matching the moment they reword one.
    ///
    /// The key is the last resort, under the same "an empty string is not a
    /// value" rule the heading and the select's empty row use: a switch with no
    /// name at all is a switch nobody can be asked about.
    private func optInCaption(_ group: FieldGroup) -> String {
        group.label(in: language).flatMap { $0.isEmpty ? nil : $0 } ?? group.key
    }

    private func optInBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { optedInGroups.contains(key) },
            set: { isOn in
                if isOn {
                    optedInGroups.insert(key)
                } else {
                    optedInGroups.remove(key)
                }
            }
        )
    }

    private func binding(group: String, field: String) -> Binding<String> {
        Binding(
            get: { values[group]?[field] ?? "" },
            set: { values[group, default: [:]][field] = $0 }
        )
    }

    private func error(group: String, field: String) -> String? {
        errors.first { $0.groupKey == group && $0.fieldName == field }?.message
    }
}

/// One server-driven field: its heading, its control and its message.
///
/// Internal rather than private so the two names it computes — the one it draws
/// and the one it speaks — can be asserted directly; nothing but this file draws
/// one. That seam exists because SwiftUI keeps its accessibility tree out of
/// reach of a unit-test bundle, measured: a hosted `TextField` reports a nil
/// `accessibilityLabel` on the `UITextField` under it however the modifier is
/// applied, and the container protocol hands back no elements at all without an
/// assistive technology running. The string is the most a test here can hold.
struct FieldRow: View {
    @Environment(\.payCrossAppearance) private var style
    /// One per row, so a tap on this row's box reaches this row's field. Same
    /// reason as the cardholder field: SwiftUI centres the control inside the
    /// frame instead of filling it, so the box has to hand the focus on.
    @FocusState private var focused: Bool
    /// Carried only so the box and its message can be addressed as
    /// `paycross.field.<group>.<name>`: two groups may name a field the same.
    let groupKey: String
    let field: FieldDefinition
    let language: String
    let state: FieldState
    @Binding var value: String
    let error: String?

    /// A select is a control of its own and handles its whole box, so it wants
    /// no tap gesture over it.
    private var isSelect: Bool { !(field.options ?? []).isEmpty }

    /// What the field is called on screen. The `*` is the sighted shopper's
    /// required marker; `accessibleName` carries the same fact in words.
    var title: String {
        let base = field.label(in: language) ?? field.name
        return state.isRequired ? "\(base) *" : base
    }

    /// What the select's empty row draws before the shopper has chosen.
    ///
    /// An empty string is not a placeholder: a session that sends `""`, or an
    /// empty entry for one language, would otherwise draw a blank row where the
    /// dash belongs. Same guard the group heading above uses.
    private var emptyRowText: String {
        // A locked select draws the dash whatever the session sent for it, for
        // the reason a locked text field draws nothing: a placeholder is an
        // invitation to type, and this one cannot be taken up.
        guard !state.isReadOnly else { return "—" }
        return field.placeholder(in: language).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }

    /// What an empty box shows before the shopper has typed.
    ///
    /// Nothing at all when the field is read-only. A locked, empty `city`
    /// drawing a grey `New York` reads as a value the merchant filled in rather
    /// than as an example, which is worse than the box merely looking editable:
    /// the shopper believes the form is answered.
    private var placeholderText: String {
        state.isReadOnly ? "" : field.placeholder(in: language) ?? ""
    }

    /// What the field is called out loud. The drawn `*` above says "required" to
    /// a shopper who can see it and nothing to one who cannot, so the spoken
    /// name says the word.
    var accessibleName: String {
        FieldGroupLogic.accessibleName(
            for: field,
            state: state,
            requiredTemplate: L("paycross_field_required_accessibility", "%@, required"),
            language: language
        )
    }

    var body: some View {
        // Label above the box, matching the card fields. Putting it inside made
        // the same form use two different field shapes, which the CI screenshot
        // showed plainly and no test could.
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                // Its words are the control's name below, and the `*` in it is
                // the word "required" there. Left visible it is a stop of its
                // own immediately before the control, so every field on the
                // form is read out twice. Same reason the amount's caption is
                // hidden.
                .accessibilityHidden(true)

            inputBox

            if let error {
                Text(error)
                    .font(style.font(.caption))
                    .foregroundStyle(style.foreground(\.error, default: Color(.systemRed)))
                    .accessibilityIdentifier(
                        PayCrossTestIdentifiers.fieldError(group: groupKey, name: field.name)
                    )
            }
        }
    }

    @ViewBuilder
    private var inputBox: some View {
        Group {
            if isSelect, let options = field.options {
                Picker(accessibleName, selection: $value) {
                    // An empty tag so an unset optional select has somewhere to sit;
                    // without it SwiftUI silently picks the first option and the
                    // shopper appears to have chosen something they did not. It
                    // draws the session's own placeholder, which for a country
                    // select is usually the one string on the form the merchant
                    // has genuinely translated; the dash is for a field that
                    // carries none.
                    Text(verbatim: emptyRowText).tag("")
                    ForEach(options, id: \.value) { option in
                        Text(option.label(in: language) ?? option.value).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(state.isReadOnly)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholderText, text: $value)
                    // Without this the spoken name is the first argument above:
                    // the shopper hears "123 Main St" on the billing line, and
                    // nothing at all on a field the merchant left no example for.
                    .accessibilityLabel(accessibleName)
                    .focused($focused)
                    .disabled(state.isReadOnly)
                    .keyboardType(field.type == "number" ? .numberPad : .default)
                    .textInputAutocapitalization(field.type == "email" ? .never : .sentences)
                    .autocorrectionDisabled(field.type == "email")
            }
        }
        // Same 44pt floor and the same reason as the card fields: the padding
        // around a `TextField` is not part of the control, so a tap in it
        // focused nothing.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // Supporting text and a muted box, for a control that is already
        // disabled and already refuses the focus. Those two carried the whole
        // message before, and neither of them draws anything: a locked field
        // was the editable box exactly, so the only way to discover the lock
        // was to tap it and watch nothing happen. The caret is absent for free,
        // because a disabled field takes no first responder.
        .payCrossMutedForeground(style, state.isReadOnly)
        .padding(.horizontal, 12)
        .payCrossComponentBackground(style, muted: state.isReadOnly)
        // A select handles its own box, and a disabled field has no focus to
        // take: a gesture over either would only eat the tap the sheet uses to
        // put the keypad away.
        .tapToFocus(isSelect || state.isReadOnly ? nil : { focused = true })
        // On the box rather than on the column around it, which is where
        // Android tags it too. On the column it was inherited by the label and
        // by the validation message, whose own `.error` identifier it replaced,
        // and `app.textFields[...]` matched the field only because the same
        // inheritance carried it down to the control anyway.
        .accessibilityIdentifier(
            PayCrossTestIdentifiers.field(group: groupKey, name: field.name)
        )
    }
}
#endif
