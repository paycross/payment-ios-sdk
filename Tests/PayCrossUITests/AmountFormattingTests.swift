#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// The Darwin-only half of `Amounts`.
///
/// `AmountsTests` in the Core bucket asserts the minor-unit table and the
/// decimal conversion, which are pure arithmetic and identical everywhere.
/// Formatted strings are not: corelibs-foundation's locale data is not
/// byte-identical to Darwin's, so asserting them on Linux is flaky. They are
/// asserted here instead, on the platform that actually ships them.
///
/// The strings the sheet draws clamp to the two languages the SDK ships. The
/// amount does not, because Foundation writes currency for any locale at all,
/// and a shopper who cannot read the labels can still read the price.
@MainActor
final class AmountFormattingTests: XCTestCase {

    override func tearDown() {
        SheetLanguage.reset()
        super.tearDown()
    }

    private let amount = Amount(minorUnits: 1234, currencyCode: "EUR")

    /// Non-breaking spaces, so a literal typed with an ordinary space fails for
    /// a reason nobody can see. Compared on digits and separators instead.
    private func normalised(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
    }

    func testFrenchPutsTheSymbolLastAndTheCommaInTheMiddle() {
        let formatted = Amounts.formatted(amount, locale: Locale(identifier: "fr-FR"))
        XCTAssertEqual(normalised(formatted), "12,34 €")
    }

    func testEnglishPutsTheSymbolFirst() {
        let formatted = Amounts.formatted(amount, locale: Locale(identifier: "en-IE"))
        XCTAssertEqual(normalised(formatted), "€12.34")
    }

    /// A zero-decimal currency keeps no fraction in either language.
    func testAZeroDecimalCurrencyShowsNoFractionInFrench() {
        let yen = Amount(minorUnits: 1234, currencyCode: "JPY")
        let formatted = Amounts.formatted(yen, locale: Locale(identifier: "fr-FR"))
        XCTAssertTrue(formatted.contains("1"), formatted)
        XCTAssertFalse(formatted.contains(","), "JPY has no minor unit: \(formatted)")
    }

    // MARK: - What the sheet actually installs

    /// The reason the resolver answers twice. Nothing here names a language the
    /// SDK ships, so the words are English — and the amount is still German.
    func testAGermanDeviceReadsItsOwnAmountUnderEnglishLabels() {
        SheetLanguage.install(LocaleResolution.resolve(device: ["de-DE"]))

        XCTAssertEqual(L("paycross_total", "MISSING"), "Total")
        XCTAssertEqual(
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "12,34 €"
        )
    }

    /// The region survives into the amount where the language drops it, so a
    /// Swiss-French session is not formatted the way France would.
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
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "12,34 €"
        )
    }
}
#endif
