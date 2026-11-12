import Foundation

package enum CardValidator {

    package static func isValidPAN(_ pan: String) -> Bool {
        let cleaned = pan.filter { !$0.isWhitespace }
        guard cleaned.count >= 13, cleaned.count <= 19 else { return false }
        guard cleaned.allSatisfy(\.isNumber) else { return false }
        return luhnCheck(cleaned)
    }

    package static func isValidExpiry(
        month: String,
        year: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let m = Int(month), let y = Int(year) else { return false }
        guard (1...12).contains(m) else { return false }

        let components = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = components.year, let currentMonth = components.month else {
            return false
        }

        let fullYear = y < 100 ? 2000 + y : y

        if fullYear < currentYear { return false }
        if fullYear == currentYear && m < currentMonth { return false }
        return true
    }

    package static func isValidCVV(_ cvv: String, brand: CardBrand) -> Bool {
        guard cvv.allSatisfy(\.isNumber) else { return false }
        return cvv.count == brand.cvvLength
    }

    package static func isValidCardholderName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func luhnCheck(_ digits: String) -> Bool {
        var sum = 0
        var alternate = false

        for character in digits.reversed() {
            guard let digit = character.wholeNumberValue else { return false }
            var value = digit
            if alternate {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
            alternate.toggle()
        }

        return sum % 10 == 0
    }
}
