import Foundation

/// Filling the one placeholder a translatable string is allowed to carry.
///
/// `String(format:)` is the obvious tool and is the wrong one here, twice over.
///
/// It is a Darwin facility for `%@` with a Swift `String`, and half the strings
/// this fills live in `PayCrossCore`, which is asserted on Linux.
///
/// And every template this touches can come from a merchant's own strings file.
/// `String(format:)` handed `"%d is required"` reads an integer vararg that was
/// never passed — undefined behaviour reached from a text file the SDK does not
/// own, on a screen that is taking a card number. Replacing a literal `%@` and
/// leaving every other percent alone cannot do that: the worst a mistyped
/// override achieves is a label that still says `%d`.
package enum Template {

    /// Substitutes the first `%@`, leaving a template without one untouched.
    ///
    /// First only, and deliberately: no string the SDK ships carries two, and a
    /// merchant override that grew a second one should lose the extra rather
    /// than have the same card name pasted into it twice.
    package static func fill(_ template: String, with value: String) -> String {
        guard let range = template.range(of: "%@") else { return template }
        return template.replacingCharacters(in: range, with: value)
    }
}
