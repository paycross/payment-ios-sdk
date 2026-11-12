import Foundation

// Templates can come from merchant strings files, so `String(format:)` is not used.
package enum Template {
    // Only the first `%@` is replaced; a second copy of a merchant value is not pasted.
    package static func fill(_ template: String, with value: String) -> String {
        guard let range = template.range(of: "%@") else { return template }
        return template.replacingCharacters(in: range, with: value)
    }

    // Each value is substituted into the remainder only, so a value containing `%@` is never replaced.
    package static func fill(
        _ template: String, with first: String, _ second: String
    ) -> String {
        guard let range = template.range(of: "%@") else { return template }
        let head = String(template[..<range.lowerBound])
        let tail = String(template[range.upperBound...])
        return head + first + fill(tail, with: second)
    }
}
