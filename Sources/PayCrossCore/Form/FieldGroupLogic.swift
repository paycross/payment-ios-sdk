import Foundation

package struct FieldState: Sendable, Equatable {
    package let isVisible: Bool
    package let isRequired: Bool
    package let isReadOnly: Bool
}

package struct FieldGroupError: Sendable, Equatable {
    package let groupKey: String
    package let fieldName: String
    package let message: String
}

package enum FieldGroupLogic {
    enum Display {
        static let hidden = "hidden"
        static let required = "required"
        static let readonly = "readonly"
    }

    package static func fieldState(
        for field: FieldDefinition,
        groupValues: [String: String]
    ) -> FieldState {
        guard let condition = field.condition else {
            return FieldState(
                isVisible: true,
                isRequired: field.required == true,
                isReadOnly: field.readonly == true
            )
        }

        let controlValue = groupValues[condition.whenField] ?? ""
        let isMet = condition.whenIn?.contains(controlValue) == true
        // A nil `default` leaves the field visible and optional, as the checkout page does.
        let display = isMet ? condition.display : condition.default

        return FieldState(
            isVisible: display != Display.hidden,
            isRequired: display == Display.required,
            isReadOnly: display == Display.readonly
        )
    }

    package static func isActive(_ group: FieldGroup, optedIn: Set<String>) -> Bool {
        !group.isOptIn || optedIn.contains(group.key)
    }

    // `validate` and `submissionValues` must agree on the active groups, so both filter through here.
    package static func activeGroups(
        _ groups: [FieldGroup], optedIn: Set<String>
    ) -> [FieldGroup] {
        groups.filter { isActive($0, optedIn: optedIn) }
    }

    // VoiceOver skips or spells out the drawn `*`, so the spoken name carries the word "required" instead.
    package static func accessibleName(
        for field: FieldDefinition,
        state: FieldState,
        requiredTemplate: String,
        language: String? = nil
    ) -> String {
        // An empty label falls back to the server's field name, not to an empty spoken name.
        let labelled = field.label(in: language).flatMap { $0.isEmpty ? nil : $0 }
        let base = labelled ?? field.name
        return state.isRequired ? Template.fill(requiredTemplate, with: base) : base
    }

    package static func initialValues(_ groups: [FieldGroup]) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for group in groups {
            var values: [String: String] = [:]
            for field in group.fields ?? [] {
                if let value = field.value, !value.isEmpty {
                    values[field.name] = value
                }
            }
            if !values.isEmpty { out[group.key] = values }
        }
        return out
    }

    package static func validate(
        groups: [FieldGroup],
        values: [String: [String: String]],
        messages: FlowMessages = .english,
        language: String? = nil
    ) -> [FieldGroupError] {
        var errors: [FieldGroupError] = []

        for group in groups {
            let groupValues = values[group.key] ?? [:]
            for field in group.fields ?? [] {
                let state = fieldState(for: field, groupValues: groupValues)
                guard state.isVisible else { continue }

                let value = groupValues[field.name] ?? ""
                let isBlank = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if state.isRequired && isBlank {
                    errors.append(FieldGroupError(
                        groupKey: group.key,
                        fieldName: field.name,
                        message: field.validation?.message("required", in: language)
                            ?? messages.requiredMessage(
                                for: field.label(in: language) ?? field.name
                            )
                    ))
                    continue
                }

                guard !isBlank else { continue }

                // Lengths count UTF-16 code units, as Kotlin and JavaScript do, so one `max_length` means one limit on all three clients.
                if let limit = field.validation?.maxLength, value.utf16.count > limit {
                    errors.append(FieldGroupError(
                        groupKey: group.key,
                        fieldName: field.name,
                        message: field.validation?.message("max_length", in: language)
                            ?? messages.tooLongMessage(
                                for: field.label(in: language) ?? field.name, limit: limit
                            )
                    ))
                    continue
                }

                guard let pattern = field.validation?.pattern else { continue }
                if !matches(value, pattern: pattern) {
                    errors.append(FieldGroupError(
                        groupKey: group.key,
                        fieldName: field.name,
                        message: field.validation?.message("pattern", in: language)
                            ?? messages.invalidMessage(
                                for: field.label(in: language) ?? field.name
                            )
                    ))
                }
            }
        }

        return errors
    }

    package static func submissionValues(
        groups: [FieldGroup],
        values: [String: [String: String]]
    ) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]

        for group in groups {
            let groupValues = values[group.key] ?? [:]
            var submitted: [String: String] = [:]
            for field in group.fields ?? [] {
                guard fieldState(for: field, groupValues: groupValues).isVisible else { continue }
                guard let value = groupValues[field.name],
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                submitted[field.name] = value
            }
            if !submitted.isEmpty { out[group.key] = submitted }
        }

        return out
    }

    // Patterns match as substrings, as Kotlin's `Regex.containsMatchIn` does; a malformed pattern passes.
    static func matches(_ value: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
