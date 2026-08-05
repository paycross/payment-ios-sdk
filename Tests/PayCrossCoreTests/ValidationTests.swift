import XCTest
@testable import PayCrossCore

final class CardBrandTests: XCTestCase {

    func testDetectsBrandsFromPrefixes() {
        XCTAssertEqual(CardBrand.detect("4111111111111111"), .visa)
        XCTAssertEqual(CardBrand.detect("5555555555554444"), .mastercard)
        XCTAssertEqual(CardBrand.detect("2223003122003222"), .mastercard)
        XCTAssertEqual(CardBrand.detect("378282246310005"), .amex)
        XCTAssertEqual(CardBrand.detect("341111111111111"), .amex)
        XCTAssertEqual(CardBrand.detect("6011111111111117"), .discover)
        XCTAssertEqual(CardBrand.detect("6511111111111119"), .discover)
    }

    func testIgnoresFormattingWhitespace() {
        XCTAssertEqual(CardBrand.detect("4111 1111 1111 1111"), .visa)
    }

    /// Android's mastercard pattern is `^(5[1-5]|2[2-7])`, so 56 and 21 are not it.
    func testPrefixBoundariesMatchTheKotlinRegexes() {
        XCTAssertEqual(CardBrand.detect("5611111111111111"), .unknown)
        XCTAssertEqual(CardBrand.detect("2111111111111111"), .unknown)
        XCTAssertEqual(CardBrand.detect("2811111111111111"), .unknown)
        // Amex is 34/37 only; 35 is not.
        XCTAssertEqual(CardBrand.detect("351111111111111"), .unknown)
        // Discover is 6011 or 65; 6012 and 66 are not.
        XCTAssertEqual(CardBrand.detect("6012111111111111"), .unknown)
        XCTAssertEqual(CardBrand.detect("6611111111111111"), .unknown)
    }

    func testEmptyAndNonNumericAreUnknown() {
        XCTAssertEqual(CardBrand.detect(""), .unknown)
        XCTAssertEqual(CardBrand.detect("abcd"), .unknown)
    }

    func testCVVLengths() {
        XCTAssertEqual(CardBrand.amex.cvvLength, 4)
        XCTAssertEqual(CardBrand.visa.cvvLength, 3)
        XCTAssertEqual(CardBrand.unknown.cvvLength, 3)
    }
}

final class CardValidatorTests: XCTestCase {

    func testAcceptsValidLuhnNumbers() {
        XCTAssertTrue(CardValidator.isValidPAN("4111111111111111"))
        XCTAssertTrue(CardValidator.isValidPAN("5555555555554444"))
        XCTAssertTrue(CardValidator.isValidPAN("378282246310005"))
        XCTAssertTrue(CardValidator.isValidPAN("4111 1111 1111 1111"))
    }

    func testRejectsBadLuhn() {
        XCTAssertFalse(CardValidator.isValidPAN("4111111111111112"))
    }

    func testRejectsOutOfRangeLengths() {
        XCTAssertFalse(CardValidator.isValidPAN("411111111111"))        // 12
        XCTAssertFalse(CardValidator.isValidPAN("41111111111111111111")) // 20
    }

    func testRejectsNonDigits() {
        XCTAssertFalse(CardValidator.isValidPAN("4111-1111-1111-1111"))
    }

    // MARK: - Expiry, pinned to a fixed "now" so these never rot

    private var june2026: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 15
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testExpiryAcceptsFutureAndCurrentMonth() {
        XCTAssertTrue(CardValidator.isValidExpiry(month: "06", year: "2026", now: june2026))
        XCTAssertTrue(CardValidator.isValidExpiry(month: "12", year: "2026", now: june2026))
        XCTAssertTrue(CardValidator.isValidExpiry(month: "01", year: "2027", now: june2026))
    }

    func testExpiryRejectsPast() {
        XCTAssertFalse(CardValidator.isValidExpiry(month: "05", year: "2026", now: june2026))
        XCTAssertFalse(CardValidator.isValidExpiry(month: "12", year: "2025", now: june2026))
    }

    func testTwoDigitYearsResolveTo2000s() {
        XCTAssertTrue(CardValidator.isValidExpiry(month: "06", year: "26", now: june2026))
        XCTAssertFalse(CardValidator.isValidExpiry(month: "05", year: "26", now: june2026))
    }

    func testExpiryRejectsBadMonths() {
        XCTAssertFalse(CardValidator.isValidExpiry(month: "00", year: "2027", now: june2026))
        XCTAssertFalse(CardValidator.isValidExpiry(month: "13", year: "2027", now: june2026))
        XCTAssertFalse(CardValidator.isValidExpiry(month: "ab", year: "2027", now: june2026))
    }

    func testCVVLengthIsBrandSpecific() {
        XCTAssertTrue(CardValidator.isValidCVV("123", brand: .visa))
        XCTAssertFalse(CardValidator.isValidCVV("1234", brand: .visa))
        XCTAssertTrue(CardValidator.isValidCVV("1234", brand: .amex))
        XCTAssertFalse(CardValidator.isValidCVV("123", brand: .amex))
        XCTAssertFalse(CardValidator.isValidCVV("12a", brand: .visa))
    }

    func testCardholderNameRejectsBlank() {
        XCTAssertTrue(CardValidator.isValidCardholderName("A Person"))
        XCTAssertFalse(CardValidator.isValidCardholderName(""))
        XCTAssertFalse(CardValidator.isValidCardholderName("   "))
    }
}

final class AmountsTests: XCTestCase {

    func testZeroDecimalCurrencies() {
        XCTAssertEqual(Amounts.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(Amounts.fractionDigits(for: "jpy"), 0)
        XCTAssertEqual(Amounts.fractionDigits(for: "KRW"), 0)
        XCTAssertEqual(Amounts.fractionDigits(for: "EUR"), 2)
        XCTAssertEqual(Amounts.fractionDigits(for: "USD"), 2)
    }

    func testMajorUnitConversionIsExact() {
        XCTAssertEqual(Amounts.majorUnits(Amount(minorUnits: 1234, currencyCode: "EUR")), Decimal(string: "12.34"))
        XCTAssertEqual(Amounts.majorUnits(Amount(minorUnits: 1234, currencyCode: "JPY")), Decimal(1234))
        XCTAssertEqual(Amounts.majorUnits(Amount(minorUnits: 5, currencyCode: "USD")), Decimal(string: "0.05"))
    }
}
