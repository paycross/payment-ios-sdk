import Foundation

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

    package var maxPANLength: Int {
        self == .amex ? 15 : 19
    }

    package static func detect(_ pan: String) -> CardBrand {
        let digits = pan.filter(\.isNumber)
        guard let first = digits.first else { return .unknown }

        switch first {
        case "4":
            return .visa
        case "5":
            return digits.hasPrefix2(in: 51...55) ? .mastercard : .unknown
        case "2":
            return digits.hasPrefix2(in: 22...27) ? .mastercard : .unknown
        case "3":
            return digits.hasPrefix2(in: 34...34) || digits.hasPrefix2(in: 37...37) ? .amex : .unknown
        case "6":
            if digits.hasPrefix("6011") { return .discover }
            return digits.hasPrefix2(in: 65...65) ? .discover : .unknown
        default:
            return .unknown
        }
    }
}

private extension String {
    func hasPrefix2(in range: ClosedRange<Int>) -> Bool {
        guard count >= 2, let value = Int(prefix(2)) else { return false }
        return range.contains(value)
    }
}
