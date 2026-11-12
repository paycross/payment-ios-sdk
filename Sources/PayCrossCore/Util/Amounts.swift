import Foundation

package enum Amounts {
    static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "GNF", "JPY", "KMF", "KRW", "MGA",
        "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]

    package static func fractionDigits(for currencyCode: String) -> Int {
        zeroDecimalCurrencies.contains(currencyCode.uppercased()) ? 0 : 2
    }

    // Decimal, not Double, keeps minor-unit division exact.
    package static func majorUnits(_ amount: Amount) -> Decimal {
        let digits = fractionDigits(for: amount.currencyCode)
        return Decimal(amount.minorUnits) / pow(Decimal(10), digits)
    }

    package static func formatted(_ amount: Amount, locale: Locale = .current) -> String {
        let digits = fractionDigits(for: amount.currencyCode)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = amount.currencyCode.uppercased()
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let value = majorUnits(amount) as NSDecimalNumber
        return formatter.string(from: value) ?? "\(value) \(amount.currencyCode.uppercased())"
    }
}
