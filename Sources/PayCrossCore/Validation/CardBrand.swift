import Foundation

/// A card scheme, detected from the leading digits of a PAN.
///
/// Mirrors `CardType` in the Android SDK, including its CVV lengths and the
/// detection order (first match wins, `unknown` last).
package enum CardBrand: String, Sendable, Hashable, CaseIterable {
    case visa
    case mastercard
    case amex
    case discover
    case unknown

    package var displayName: String {
        switch self {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "American Express"
        case .discover: "Discover"
        case .unknown: "Card"
        }
    }

    package var cvvLength: Int {
        self == .amex ? 4 : 3
    }

    /// The maximum PAN length this brand accepts, used to bound input.
    package var maxPANLength: Int {
        self == .amex ? 15 : 19
    }

    /// Detects the brand from a PAN, ignoring whitespace.
    ///
    /// Android matches on prefix regexes with `containsMatchIn`, which is anchored
    /// by the leading `^` in every pattern; these are the same prefixes expressed
    /// as literal comparisons so no regex engine is needed.
    package static func detect(_ pan: String) -> CardBrand {
        let digits = pan.filter(\.isNumber)
        guard let first = digits.first else { return .unknown }

        switch first {
        case "4":
            return .visa
        case "5":
            // 51-55
            return digits.hasPrefix2(in: 51...55) ? .mastercard : .unknown
        case "2":
            // 22-27
            return digits.hasPrefix2(in: 22...27) ? .mastercard : .unknown
        case "3":
            // 34, 37
            return digits.hasPrefix2(in: 34...34) || digits.hasPrefix2(in: 37...37) ? .amex : .unknown
        case "6":
            // 6011 or 65
            if digits.hasPrefix("6011") { return .discover }
            return digits.hasPrefix2(in: 65...65) ? .discover : .unknown
        default:
            return .unknown
        }
    }
}

private extension String {
    /// Whether the first two characters, read as a number, fall in `range`.
    func hasPrefix2(in range: ClosedRange<Int>) -> Bool {
        guard count >= 2, let value = Int(prefix(2)) else { return false }
        return range.contains(value)
    }
}
