#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class AmountFormattingTests: XCTestCase {

    override func tearDown() {
        SheetLanguage.reset()
        super.tearDown()
    }

    private let amount = Amount(minorUnits: 2599, currencyCode: "EUR")

    private func normalised(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
    }

    func testFrenchPutsTheSymbolLastAndTheCommaInTheMiddle() {
        let formatted = Amounts.formatted(amount, locale: Locale(identifier: "fr-FR"))
        XCTAssertEqual(normalised(formatted), "25,99 €")
    }

    func testEnglishPutsTheSymbolFirst() {
        let formatted = Amounts.formatted(amount, locale: Locale(identifier: "en-IE"))
        XCTAssertEqual(normalised(formatted), "€25.99")
    }

    func testAZeroDecimalCurrencyShowsNoFractionInFrench() {
        let yen = Amount(minorUnits: 1234, currencyCode: "JPY")
        let formatted = Amounts.formatted(yen, locale: Locale(identifier: "fr-FR"))
        XCTAssertTrue(formatted.contains("1"), formatted)
        XCTAssertFalse(formatted.contains(","), "JPY has no minor unit: \(formatted)")
    }

    // MARK: - What the sheet actually installs

    func testADeviceOnlySheetFormatsExactlyAsItDidBeforeFrench() {
        SheetLanguage.install(LocaleResolution.resolve(device: ["de-DE"]))

        XCTAssertEqual(L("paycross_total", "MISSING"), "Total")
        XCTAssertEqual(SheetLanguage.locale, .current)
        XCTAssertEqual(
            Amounts.formatted(amount, locale: SheetLanguage.locale),
            Amounts.formatted(amount),
            "the default parameter is Locale.current; these must not diverge"
        )
    }

    func testAnAskedForGermanTagReadsItsOwnAmountUnderEnglishLabels() {
        SheetLanguage.install(LocaleResolution.resolve(override: "de-DE"))

        XCTAssertEqual(L("paycross_total", "MISSING"), "Total")
        XCTAssertEqual(
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "25,99 €"
        )
    }

    func testASwissFrenchSessionIsNotFormattedLikeFrance() {
        SheetLanguage.install(LocaleResolution.resolve(session: "fr-CH"))
        let swiss = normalised(Amounts.formatted(amount, locale: SheetLanguage.locale))

        XCTAssertEqual(L("paycross_total", "MISSING"), "Total")
        XCTAssertEqual(SheetLanguage.locale.identifier, "fr-CH")
        XCTAssertNotEqual(
            swiss, normalised(Amounts.formatted(amount, locale: Locale(identifier: "fr-FR"))),
            "fr-CH and fr-FR write this amount differently; the region must survive"
        )
    }

    func testTheSheetFormatsInFrenchOnceFrenchIsInstalled() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr-FR"))
        XCTAssertEqual(
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "25,99 €"
        )
    }
}
#endif
