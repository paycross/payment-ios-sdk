import XCTest
@testable import PayCrossCore

/// The one rule that decides what language the sheet speaks and how it writes an
/// amount. It is pure and it lives in Core precisely so it is asserted on Linux
/// on every commit: the bundle lookup it feeds only compiles on a Mac, so this is
/// the half that can be proved cheaply and often.
final class LocaleResolutionTests: XCTestCase {

    private func language(
        override: String? = nil, session: String? = nil, device: [String] = []
    ) -> String {
        LocaleResolution.resolve(override: override, session: session, device: device).language
    }

    private func formatting(
        override: String? = nil, session: String? = nil, device: [String] = []
    ) -> String {
        LocaleResolution.resolve(override: override, session: session, device: device).formattingTag
    }

    // MARK: - The ladder

    func testNothingToGoOnIsEnglish() {
        XCTAssertEqual(language(), "en")
    }

    func testTheMerchantOverrideWins() {
        XCTAssertEqual(language(override: "fr", session: "en", device: ["en-US"]), "fr")
    }

    func testTheSessionWinsOverTheDevice() {
        XCTAssertEqual(language(session: "fr", device: ["en-US"]), "fr")
    }

    func testTheDeviceDecidesWhenNobodyElseSpeaks() {
        XCTAssertEqual(language(device: ["fr-FR"]), "fr")
    }

    // MARK: - Falling through

    /// A candidate naming a language the SDK does not ship is passed over, not
    /// treated as the final answer. A merchant asking for German over a French
    /// session gets the French sheet, because French is a language this shopper
    /// was already going to be shown and German is one nobody can be. Same rule
    /// as the hosted checkout page, which matches each candidate separately.
    func testAnUnsupportedOverrideGivesTheSessionItsTurn() {
        XCTAssertEqual(language(override: "de", session: "fr", device: ["en-US"]), "fr")
    }

    func testAnUnsupportedSessionGivesTheDeviceItsTurn() {
        XCTAssertEqual(language(session: "de", device: ["fr-FR"]), "fr")
    }

    func testWhenNoRungNamesALanguageWeShipItIsEnglish() {
        XCTAssertEqual(language(override: "de", device: ["de-DE"]), "en")
    }

    /// An empty string is not an answer. A merchant reading their own config into
    /// `locale:` should get the session's language, not the default.
    func testABlankOverrideStillLetsTheSessionAndDeviceSpeak() {
        XCTAssertEqual(language(override: "  ", session: "fr"), "fr")
        XCTAssertEqual(language(override: "", device: ["fr-FR"]), "fr")
    }

    func testAMalformedOverrideStillLetsTheSessionSpeak() {
        for tag in ["-", "---", "!!", "-fr", "123"] {
            XCTAssertEqual(
                language(override: tag, session: "fr"), "fr",
                "\(tag.debugDescription) should be passed over, not resolve the sheet"
            )
        }
    }

    func testABlankSessionLocaleIsNoAnswer() {
        XCTAssertEqual(language(session: "", device: ["fr"]), "fr")
    }

    // MARK: - Matching one tag

    func testAnExactTagMatches() {
        XCTAssertEqual(language(override: "fr"), "fr")
    }

    func testARegionalTagMatchesOnItsPrimarySubtag() {
        XCTAssertEqual(language(override: "fr-CA"), "fr")
    }

    func testAScriptAndRegionTagMatchesOnItsPrimarySubtag() {
        XCTAssertEqual(language(override: "fr-Latn-CA"), "fr")
    }

    /// `Locale.identifier` and server payloads both hand out POSIX-style tags.
    func testAnUnderscoreSeparatorIsAccepted() {
        XCTAssertEqual(language(override: "fr_CA"), "fr")
    }

    func testMatchingIgnoresCase() {
        XCTAssertEqual(language(override: "FR-ca"), "fr")
    }

    func testTheResolvedLanguageIsAlwaysLowercased() {
        XCTAssertEqual(language(override: "EN"), "en")
    }

    // MARK: - The device's ranked preferences

    func testTheDeviceListIsScannedInOrder() {
        XCTAssertEqual(language(device: ["de-DE", "fr-FR", "en"]), "fr")
    }

    /// Each candidate is tried exact-then-subtag before the next one is looked
    /// at. Sweeping the whole list for exact matches first would hand a shopper
    /// who ranked Canadian French above English the English sheet.
    func testARegionalPreferenceBeatsALaterExactMatch() {
        XCTAssertEqual(language(device: ["fr-CA", "en"]), "fr")
    }

    func testADeviceThatSpeaksNothingWeShipIsEnglish() {
        XCTAssertEqual(language(device: ["de-DE", "ja-JP"]), "en")
    }

    func testADeviceListOfBlanksIsEnglish() {
        XCTAssertEqual(language(device: ["", "  "]), "en")
    }

    // MARK: - Formatting is a separate answer, and is not clamped

    /// The strings clamp to what the SDK ships; the amount does not, because
    /// Foundation formats currency for any locale at all. A shopper on a German
    /// phone reads `12,34 €` under English labels rather than `€12.34`.
    func testAnUnsupportedDeviceStillFormatsInItsOwnLocale() {
        let resolved = LocaleResolution.resolve(device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    /// The region is kept where the language drops it, which is the whole point:
    /// Swiss French does not write an amount the way France does.
    func testTheRegionSurvivesIntoTheFormattingTag() {
        let resolved = LocaleResolution.resolve(session: "fr-CH")
        XCTAssertEqual(resolved.language, "fr")
        XCTAssertEqual(resolved.formattingTag, "fr-CH")
    }

    func testFormattingTakesTheFirstCandidateAnybodySupplied() {
        XCTAssertEqual(formatting(override: "de", session: "fr", device: ["en-US"]), "de")
        XCTAssertEqual(formatting(session: "fr-CA", device: ["en-US"]), "fr-CA")
        XCTAssertEqual(formatting(device: ["ja-JP", "en-US"]), "ja-JP")
    }

    func testFormattingSkipsBlanksLikeTheLanguageDoes() {
        XCTAssertEqual(formatting(override: "  ", session: "fr-CH"), "fr-CH")
    }

    func testFormattingIsEnglishWhenNobodySuppliedAnything() {
        XCTAssertEqual(formatting(), "en")
    }

    /// `fr_CH` and `fr-CH` are the same locale, and Foundation is happier with
    /// one of them. The case is left alone, because a region subtag is
    /// conventionally uppercase and this string goes straight into a `Locale`.
    func testTheFormattingTagIsNormalisedButNotLowercased() {
        XCTAssertEqual(formatting(session: " fr_CH "), "fr-CH")
    }

    // MARK: - What ships

    func testTheSDKShipsEnglishAndFrench() {
        XCTAssertEqual(LocaleResolution.supportedLanguages, ["en", "fr"])
    }

    func testTheDefaultLanguageIsTheOneThePackageDeclares() {
        XCTAssertEqual(LocaleResolution.defaultLanguage, "en")
    }
}
