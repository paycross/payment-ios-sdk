import XCTest
@testable import PayCrossCore

final class LocaleResolutionTests: XCTestCase {

    private func language(
        override: String? = nil, session: String? = nil, device: [String] = []
    ) -> String {
        LocaleResolution.resolve(override: override, session: session, device: device).language
    }

    private func formatting(
        override: String? = nil, session: String? = nil, device: [String] = []
    ) -> String? {
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

    func testAnUnsupportedOverrideGivesTheSessionItsTurn() {
        XCTAssertEqual(language(override: "de", session: "fr", device: ["en-US"]), "fr")
    }

    func testAnUnsupportedSessionGivesTheDeviceItsTurn() {
        XCTAssertEqual(language(session: "de", device: ["fr-FR"]), "fr")
    }

    func testWhenNoRungNamesALanguageWeShipItIsEnglish() {
        XCTAssertEqual(language(override: "de", device: ["de-DE"]), "en")
    }

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

    func testAnUnderscoreSeparatorIsAccepted() {
        XCTAssertEqual(language(override: "fr_CA"), "fr")
    }

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

    func testTheDeviceNeverSuppliesAFormattingTag() {
        let resolved = LocaleResolution.resolve(device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en")
        XCTAssertNil(resolved.formattingTag, "the device's own Locale is better than its tag")
    }

    func testAnAskedForTagWeShipNoWordsForStillFormats() {
        let resolved = LocaleResolution.resolve(override: "de-AT")
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-AT")
    }

    func testTheRegionSurvivesIntoTheFormattingTag() {
        let resolved = LocaleResolution.resolve(session: "fr-CH")
        XCTAssertEqual(resolved.language, "fr")
        XCTAssertEqual(resolved.formattingTag, "fr-CH")
    }

    func testFormattingTakesTheFirstTagSomebodyAskedFor() {
        XCTAssertEqual(formatting(override: "de", session: "fr", device: ["en-US"]), "de")
        XCTAssertEqual(formatting(session: "fr-CA", device: ["en-US"]), "fr-CA")
        XCTAssertNil(formatting(device: ["ja-JP", "en-US"]), "the device is not asked for")
    }

    func testFormattingSkipsBlanksLikeTheLanguageDoes() {
        XCTAssertEqual(formatting(override: "  ", session: "fr-CH"), "fr-CH")
    }

    func testFormattingIsUnsetWhenNobodyAskedForAnything() {
        XCTAssertNil(formatting())
    }

    func testTheFormattingTagIsNormalisedButNotLowercased() {
        XCTAssertEqual(formatting(session: " fr_CH "), "fr-CH")
    }

    // MARK: - A tag that is not shaped like one never formats an amount

    func testAMalformedCandidateDoesNotFormatTheAmount() {
        for typo in [
            "français", "f-r", "f", "frenchy", "fr!", "fr-", "-fr", "fr--CA", "123",
            "fr-CAAAAAAAAA"
        ] {
            XCTAssertNil(
                formatting(override: typo, device: ["de-DE"]),
                "\(typo.debugDescription) is not shaped like a language tag"
            )
            XCTAssertEqual(
                formatting(override: typo, session: "de-DE"), "de-DE",
                "\(typo.debugDescription) must leave the session its turn"
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

    func testWhenNoAskedForTagIsWellFormedTheAmountIsUnset() {
        XCTAssertNil(formatting(override: "f-r", session: "!!", device: ["fr-FR"]))
    }

    func testALanguageNameInsteadOfATagPicksNeitherTheWordsNorTheFormat() {
        let resolved = LocaleResolution.resolve(override: "français", session: "de-DE")
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-DE", "the session gets its turn at both")
    }

    func testASingleLetterIsNotATag() {
        let resolved = LocaleResolution.resolve(override: "f", session: "de-DE")
        XCTAssertEqual(resolved.language, "en")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    func testAMalformedCandidateCanStillChooseTheLanguage() {
        let resolved = LocaleResolution.resolve(override: "fr-", session: "de-DE")
        XCTAssertEqual(resolved.language, "fr")
        XCTAssertEqual(resolved.formattingTag, "de-DE")
    }

    func testAWellFormedTagWeShipNoStringsForStillFormatsTheAmount() {
        let resolved = LocaleResolution.resolve(override: "frr", device: ["de-DE"])
        XCTAssertEqual(resolved.language, "en", "the SDK ships no Frisian")
        XCTAssertEqual(resolved.formattingTag, "frr")
    }

    func testTheSupportedSetIsMatchedWhateverCaseItIsWrittenIn() {
        XCTAssertEqual(
            LocaleResolution.resolve(override: "EN-gb", supported: ["EN", "FR"]).language, "en"
        )
    }

    // MARK: - What ships

    func testTheSDKShipsEnglishAndFrench() {
        XCTAssertEqual(LocaleResolution.supportedLanguages, ["en", "fr"])
    }

    func testTheDefaultLanguageIsTheOneThePackageDeclares() {
        XCTAssertEqual(LocaleResolution.defaultLanguage, "en")
    }
}
