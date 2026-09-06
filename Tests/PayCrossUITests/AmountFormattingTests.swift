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

    /// The amount the French screenshots render, so the assertions and the
    /// pictures say the same thing.
    private let amount = Amount(minorUnits: 2599, currencyCode: "EUR")

    /// Non-breaking spaces, so a literal typed with an ordinary space fails for
    /// a reason nobody can see. Compared on digits and separators instead.
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

    /// A zero-decimal currency keeps no fraction in either language.
    func testAZeroDecimalCurrencyShowsNoFractionInFrench() {
        let yen = Amount(minorUnits: 1234, currencyCode: "JPY")
        let formatted = Amounts.formatted(yen, locale: Locale(identifier: "fr-FR"))
        XCTAssertTrue(formatted.contains("1"), formatted)
        XCTAssertFalse(formatted.contains(","), "JPY has no minor unit: \(formatted)")
    }

    // MARK: - What the sheet actually installs

    /// A device nobody overrode formats with `Locale.current`, which is what the
    /// SDK did before it spoke a second language. A locale rebuilt from the
    /// device's language list would drop the shopper's Region and their explicit
    /// format settings, and rewrite the price for everyone whose Region does not
    /// simply follow their language.
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

    /// The reason the resolver answers twice: an asked-for tag the SDK ships no
    /// words for still writes the price its own way.
    func testAnAskedForGermanTagReadsItsOwnAmountUnderEnglishLabels() {
        SheetLanguage.install(LocaleResolution.resolve(override: "de-DE"))

        XCTAssertEqual(L("paycross_total", "MISSING"), "Total")
        XCTAssertEqual(
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "25,99 €"
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
            normalised(Amounts.formatted(amount, locale: SheetLanguage.locale)), "25,99 €"
        )
    }
}
#endif
