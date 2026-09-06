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

    /// A merchant reading `Locale.current.identifier` straight into `locale:`
    /// hands over `fr_FR`. It has to behave as `fr-FR` on both halves at once,
    /// or the words come out French and the price comes out of the fallback.
    func testAPOSIXStyleTagBehavesAsItsHyphenatedForm() {
        let underscored = LocaleResolution.resolve(override: "fr_FR")
        XCTAssertEqual(underscored, LocaleResolution.resolve(override: "fr-FR"))
        XCTAssertEqual(underscored.language, "fr")
        XCTAssertEqual(underscored.formattingTag, "fr-FR")
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

    // MARK: - A tag that is not shaped like one never formats an amount

    /// `Locale(identifier:)` accepts anything and quietly formats nonsense with
    /// root data, so a typo would otherwise do double damage: wrong words *and*
    /// a wrong price format. A candidate that is not shaped like a language tag
    /// is passed over for formatting, and the next one supplies it.
    func testAMalformedCandidateDoesNotFormatTheAmount() {
        for typo in [
            "français", "f-r", "f", "frenchy", "fr!", "fr-", "-fr", "fr--CA", "123",
            "fr-CAAAAAAAAA"
        ] {
            XCTAssertEqual(
                formatting(override: typo, device: ["de-DE"]), "de-DE",
                "\(typo.debugDescription) is not shaped like a language tag"
            )
        }
    }

    func testWellFormedTagsAreAcceptedForFormatting() {
        for tag in ["fr", "en", "fr-CA", "de-DE", "fr-Latn-CA", "zh-Hant-TW", "es-419"] {
            XCTAssertEqual(
                formatting(override: tag), tag,
                "\(tag.debugDescription) is shaped like a language tag"
            )
        }
    }

    func testWhenNoCandidateIsWellFormedTheAmountIsEnglish() {
        XCTAssertEqual(formatting(override: "f-r", session: "!!", device: ["-"]), "en")
    }

    /// The shape of typo this rule is for: a merchant who wrote the language's
    /// name where its tag belongs. It picks neither the words nor the number
    /// format, and the device supplies both.
    func testALanguageNameInsteadOfATagPicksNeitherTheWordsNorTheFormat() {
        let resolved = LocaleResolution.resolve(override: "français", device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    func testASingleLetterIsNotATag() {
        let resolved = LocaleResolution.resolve(override: "f", device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    /// The words are more forgiving than the amount, on purpose. `fr-` is a typo
    /// that plainly means French and reads as French; it just does not get to
    /// decide how a price is written.
    func testAMalformedCandidateCanStillChooseTheLanguage() {
        let resolved = LocaleResolution.resolve(override: "fr-", device: ["de-DE"])
        XCTAssertEqual(resolved.language, "fr")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    /// The two clamps are different, and this is the case that shows it. `frr`
    /// is Northern Frisian: a real language, a well-formed tag, and one the SDK
    /// ships no strings for. So the words fall through to English while the
    /// amount is formatted as Frisian, which is exactly the point of leaving
    /// formatting unclamped — Foundation has number formats for far more
    /// languages than this SDK has words.
    func testAWellFormedTagWeShipNoStringsForStillFormatsTheAmount() {
        let resolved = LocaleResolution.resolve(override: "frr", device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en", "the SDK ships no Frisian")
        XCTAssertEqual(resolved.formattingTag, "frr")
    }

    // MARK: - What ships

    func testTheSDKShipsEnglishAndFrench() {
        XCTAssertEqual(LocaleResolution.supportedLanguages, ["en", "fr"])
    }

    func testTheDefaultLanguageIsTheOneThePackageDeclares() {
        XCTAssertEqual(LocaleResolution.defaultLanguage, "en")
    }
}
