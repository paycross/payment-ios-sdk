import Foundation

/// Whether a server-driven field is shown, and how it behaves when it is.
public struct FieldState: Sendable, Equatable {
    public let isVisible: Bool
    public let isRequired: Bool
    public let isReadOnly: Bool
}

public struct FieldGroupError: Sendable, Equatable {
    public let groupKey: String
    public let fieldName: String
    public let message: String
}

/// The checkout page's field-group semantics.
///
/// A field's condition is evaluated against its *siblings in the same group*, and
/// only visible fields are validated or submitted. Pure, so all of it is asserted
/// on Linux — which matters, because these rules are server-driven and a mistake
/// shows up as a field that silently never appears.
public enum FieldGroupLogic {

    /// Display keywords the server can send.
    enum Display {
        static let hidden = "hidden"
        static let required = "required"
        static let readonly = "readonly"
    }

    public static func fieldState(
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
        // When the condition is not met the `default` display applies. A nil
        // default therefore leaves the field visible and optional, which is what
        // the checkout page does.
        let display = isMet ? condition.display : condition.default

        return FieldState(
            isVisible: display != Display.hidden,
            isRequired: display == Display.required,
            isReadOnly: display == Display.readonly
        )
    }

    /// Server-supplied starting values, keyed by group. Empty groups are dropped.
    public static func initialValues(_ groups: [FieldGroup]) -> [String: [String: String]] {
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

    /// Validates visible fields only.
    ///
    /// Ordered deterministically — group order then field order, as the server
    /// sent them — so the first error shown to a shopper is stable.
    public static func validate(
        groups: [FieldGroup],
        values: [String: [String: String]]
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
                        message: field.validation?.messages?["required"]
                            ?? "\(field.label ?? field.name) is required"
                    ))
                    continue
                }

                guard !isBlank, let pattern = field.validation?.pattern else { continue }
                if !matches(value, pattern: pattern) {
                    errors.append(FieldGroupError(
                        groupKey: group.key,
                        fieldName: field.name,
                        message: field.validation?.messages?["pattern"]
                            ?? "\(field.label ?? field.name) is invalid"
                    ))
                }
            }
        }

        return errors
    }

    /// What goes on the wire under `field_groups`: visible fields with non-blank
    /// values, empty groups dropped.
    public static func submissionValues(
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

    /// Substring match, mirroring Kotlin's `Regex.containsMatchIn` — an unanchored
    /// server pattern must not be silently treated as a whole-string match.
    ///
    /// A malformed pattern passes rather than rejecting the shopper's input: the
    /// server validates too, and a broken rule must not make checkout impossible.
    static func matches(_ value: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
