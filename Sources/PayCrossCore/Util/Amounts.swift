import Foundation

/// Minor-unit handling for ISO 4217 amounts.
///
/// `fractionDigits` is a pure table lookup and is asserted on Linux. Currency
/// *formatting* is deliberately kept separate: corelibs-foundation's locale data
/// is not byte-identical to Darwin's, so asserting formatted strings on Linux
/// produces flaky results. Format assertions belong in the Darwin-only test bucket.
package enum Amounts {

    /// ISO 4217 currencies with no minor unit — minor units equal major units.
    static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "GNF", "JPY", "KMF", "KRW", "MGA",
        "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]

    package static func fractionDigits(for currencyCode: String) -> Int {
        zeroDecimalCurrencies.contains(currencyCode.uppercased()) ? 0 : 2
    }

    /// Converts minor units to their major-unit decimal value.
    ///
    /// Uses `Decimal` rather than `Double` so 1/100ths are exact.
    package static func majorUnits(_ amount: Amount) -> Decimal {
        let digits = fractionDigits(for: amount.currencyCode)
        return Decimal(amount.minorUnits) / pow(Decimal(10), digits)
    }

    /// Formats an amount as a localised currency string.
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
