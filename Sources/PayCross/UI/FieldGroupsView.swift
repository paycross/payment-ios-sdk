#if os(iOS)
import SwiftUI
import PayCrossCore

/// Renders the server-driven field groups.
///
/// Every decision about whether a field shows, is required, or is submitted lives
/// in `FieldGroupLogic` in Core. This file only draws what that logic decides,
/// which is why the conditional-display rules are asserted on Linux.
struct FieldGroupsView: View {
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
                            .font(.subheadline.weight(.semibold))
                    }

                    ForEach(visible, id: \.name) { field in
                        let state = FieldGroupLogic.fieldState(
                            for: field, groupValues: groupValues
                        )
                        FieldRow(
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
    let field: FieldDefinition
    let state: FieldState
    @Binding var value: String
    let error: String?

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
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            inputBox

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color(.systemRed))
            }
        }
        .accessibilityIdentifier("field-\(field.name)")
    }

    @ViewBuilder
    private var inputBox: some View {
        Group {
            if let options = field.options, !options.isEmpty {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
#endif
