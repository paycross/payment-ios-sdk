#if os(iOS)
import SwiftUI
import PayCrossCore

struct FieldGroupsView: View {
    @Environment(\.payCrossAppearance) private var style
    let groups: [FieldGroup]
    @Binding var values: [String: [String: String]]
    @Binding var optedInGroups: Set<String>
    let errors: [FieldGroupError]
    // WHY: The sheet passes the language in, since wire strings must match the language tag of the rest of the chrome.
    let language: String

    var body: some View {
        ForEach(groups, id: \.key) { group in
            let groupValues = values[group.key] ?? [:]
            // A declined group draws no fields, matching the validation and submission.
            let visible = FieldGroupLogic.isActive(group, optedIn: optedInGroups)
                ? (group.fields ?? []).filter {
                    FieldGroupLogic.fieldState(for: $0, groupValues: groupValues).isVisible
                }
                : []

            // WHY: An opt-in group stays on screen with no fields, since its toggle is the only way to opt in.
            if group.isOptIn || !visible.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if group.isOptIn {
                        // WHY: The toggle carries the group's heading, so the heading is not drawn again above it.
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

struct FieldRow: View {
    @Environment(\.payCrossAppearance) private var style
    // WHY: SwiftUI centres the control in its frame, so the box hands the tap on to the field.
    @FocusState private var focused: Bool
    // WHY: Two groups may name a field the same, so the identifiers need the group key.
    let groupKey: String
    let field: FieldDefinition
    let language: String
    let state: FieldState
    @Binding var value: String
    let error: String?

    private var isSelect: Bool { !(field.options ?? []).isEmpty }

    var title: String {
        let base = field.label(in: language) ?? field.name
        return state.isRequired ? "\(base) *" : base
    }

    private var emptyRowText: String {
        // WHY: A locked select draws the dash, since a placeholder invites typing that a locked field cannot take up.
        guard !state.isReadOnly else { return "—" }
        return field.placeholder(in: language).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }

    // WHY: A read-only field shows no placeholder, or it reads as a value the merchant filled in.
    private var placeholderText: String {
        state.isReadOnly ? "" : field.placeholder(in: language) ?? ""
    }

    // WHY: The drawn * means "required" only to a sighted shopper, so the spoken name carries the word.
    var accessibleName: String {
        FieldGroupLogic.accessibleName(
            for: field,
            state: state,
            requiredTemplate: L("paycross_field_required_accessibility", "%@, required"),
            language: language
        )
    }

    var body: some View {
        // WHY: The label sits above the box, as on the card fields, so every form uses one field shape.
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                // WHY: The label's words are the control's name below, so VoiceOver would read the field twice.
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
                    // WHY: Without an empty tag SwiftUI silently selects the first option, as if the shopper had chosen it.
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
                    // WHY: Without this the label is the placeholder, so the shopper hears an example value, not the field name.
                    .accessibilityLabel(accessibleName)
                    .focused($focused)
                    .disabled(state.isReadOnly)
                    .keyboardType(field.type == "number" ? .numberPad : .default)
                    .textInputAutocapitalization(field.type == "email" ? .never : .sentences)
                    .autocorrectionDisabled(field.type == "email")
            }
        }
        // WHY: The padding around a TextField is not part of the control, so a tap in it focused nothing.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // WHY: A locked field looks muted, since otherwise it looks editable and the shopper taps it for nothing.
        .payCrossMutedForeground(style, state.isReadOnly)
        .padding(.horizontal, 12)
        .payCrossComponentBackground(style, muted: state.isReadOnly)
        // WHY: A select handles its own box, and a gesture over a disabled field would eat the tap that dismisses the keypad.
        .tapToFocus(isSelect || state.isReadOnly ? nil : { focused = true })
        // WHY: The identifier sits on the box, not the column, or the label and error message would inherit it.
        .accessibilityIdentifier(
            PayCrossTestIdentifiers.field(group: groupKey, name: field.name)
        )
    }
}
#endif
