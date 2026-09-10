import Foundation

/// Whether a server-driven field is shown, and how it behaves when it is.
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

/// The checkout page's field-group semantics.
///
/// A field's condition is evaluated against its *siblings in the same group*, and
/// only visible fields are validated or submitted. Pure, so all of it is asserted
/// on Linux — which matters, because these rules are server-driven and a mistake
/// shows up as a field that silently never appears.
package enum FieldGroupLogic {

    /// Display keywords the server can send.
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

    /// Whether a group's fields are drawn, validated and submitted at all.
    ///
    /// An opt-in group is none of those until the shopper ticks it: the
    /// merchant asked to offer that group, not to require it. Every other group
    /// always counts, whatever the set holds -- the flag on the group is what
    /// makes it declinable, not membership of a set a caller happens to carry.
    package static func isActive(_ group: FieldGroup, optedIn: Set<String>) -> Bool {
        !group.isOptIn || optedIn.contains(group.key)
    }

    /// The groups that count right now, in the order the server sent them.
    ///
    /// Filtering here rather than teaching `validate` and `submissionValues`
    /// about opt-in separately: those two must always agree about which groups
    /// exist, and a caller that forgets to filter gets the behaviour the SDK
    /// had before opt-in rather than a shipping address quietly dropped from a
    /// submission the shopper did fill in.
    package static func activeGroups(
        _ groups: [FieldGroup], optedIn: Set<String>
    ) -> [FieldGroup] {
        groups.filter { isActive($0, optedIn: optedIn) }
    }

    /// What an assistive technology should call a field.
    ///
    /// The drawn heading marks a required field with a trailing `*`, which is a
    /// glyph VoiceOver either skips or spells out as "star"; the spoken name has
    /// to carry the word instead. Required-ness is read off the `FieldState`
    /// rather than off `field.required`, because a condition can make an
    /// otherwise optional field required.
    ///
    /// - Parameter requiredTemplate: the sheet's own "%@, required" copy,
    ///   already looked up. Handed in for the same reason `FlowMessages` is:
    ///   Core ships no strings and cannot reach the merchant-first lookup.
    package static func accessibleName(
        for field: FieldDefinition,
        state: FieldState,
        requiredTemplate: String,
        language: String? = nil
    ) -> String {
        // An empty label is not a name. Without this the one field the fix is
        // for — the one nothing on screen identifies — would get an explicitly
        // empty name instead of falling through to what the server called it.
        let labelled = field.label(in: language).flatMap { $0.isEmpty ? nil : $0 }
        let base = labelled ?? field.name
        return state.isRequired ? Template.fill(requiredTemplate, with: base) : base
    }

    /// Server-supplied starting values, keyed by group. Empty groups are dropped.
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

    /// Validates visible fields only: required, then the server's length limit,
    /// then its pattern, and at most one complaint per field.
    ///
    /// Ordered deterministically — group order then field order, as the server
    /// sent them — so the first error shown to a shopper is stable.
    ///
    /// - Parameter messages: the fallback sentences, resolved by the sheet. A
    ///   message the server sent with the field still wins over both: it is
    ///   written for that one field.
    /// - Parameter language: which of the server's own sentences to take. It
    ///   sends each of them in every language the checkout renders; nil reads the
    ///   single sentence, which is all a session minted before those existed
    ///   carries.
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

                // A blank value is nobody's business but the required rule's:
                // it is never too long, it is dropped before submission, and an
                // optional field left alone must not be told it failed a pattern.
                guard !isBlank else { continue }

                // Counted in UTF-16 code units, which is what Kotlin's
                // `String.length` and JavaScript's `String.slice` count, so one
                // `max_length` means one limit on all three clients. Swift's own
                // `count` is grapheme clusters, and a shopper pasting an
                // accented name would otherwise be told a different thing here
                // than on the checkout page.
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

    /// What goes on the wire under `field_groups`: visible fields with non-blank
    /// values, empty groups dropped.
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
