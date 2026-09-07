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
    let errors: [FieldGroupError]

    var body: some View {
        ForEach(groups, id: \.key) { group in
            let groupValues = values[group.key] ?? [:]
            let visible = (group.fields ?? []).filter {
                FieldGroupLogic.fieldState(for: $0, groupValues: groupValues).isVisible
            }

            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if let label = group.label, !label.isEmpty {
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
                            state: state,
                            value: binding(group: group.key, field: field.name),
                            error: error(group: group.key, field: field.name)
                        )
                    }
                }
            }
        }
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

private struct FieldRow: View {
    @Environment(\.payCrossAppearance) private var style
    /// One per row, so a tap on this row's box reaches this row's field. Same
    /// reason as the cardholder field: SwiftUI centres the control inside the
    /// frame instead of filling it, so the box has to hand the focus on.
    @FocusState private var focused: Bool
    /// Carried only so the box and its message can be addressed as
    /// `paycross.field.<group>.<name>`: two groups may name a field the same.
    let groupKey: String
    let field: FieldDefinition
    let state: FieldState
    @Binding var value: String
    let error: String?

    /// A select is a control of its own and handles its whole box, so it wants
    /// no tap gesture over it.
    private var isSelect: Bool { !(field.options ?? []).isEmpty }

    private var title: String {
        let base = field.label ?? field.name
        return state.isRequired ? "\(base) *" : base
    }

    var body: some View {
        // Label above the box, matching the card fields. Putting it inside made
        // the same form use two different field shapes, which the CI screenshot
        // showed plainly and no test could.
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))

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
                Picker(title, selection: $value) {
                    // An empty tag so an unset optional select has somewhere to sit;
                    // without it SwiftUI silently picks the first option and the
                    // shopper appears to have chosen something they did not.
                    Text(verbatim: "—").tag("")
                    ForEach(options, id: \.value) { option in
                        Text(option.label ?? option.value).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(state.isReadOnly)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(field.placeholder ?? "", text: $value)
                    .focused($focused)
                    .disabled(state.isReadOnly)
                    .keyboardType(field.type == "number" ? .numberPad : .default)
                    .textInputAutocapitalization(field.type == "email" ? .never : .sentences)
                    .autocorrectionDisabled(field.type == "email")
                    .onChange(of: value) { newValue in
                        // Enforce the server's max length as the shopper types.
                        if let max = field.validation?.maxLength, newValue.count > max {
                            value = String(newValue.prefix(max))
                        }
                    }
            }
        }
        // Same 44pt floor and the same reason as the card fields: the padding
        // around a `TextField` is not part of the control, so a tap in it
        // focused nothing.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .payCrossComponentBackground(style)
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
