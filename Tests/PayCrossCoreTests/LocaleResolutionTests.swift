import XCTest
@testable import PayCrossCore

/// The one rule that decides what language the sheet speaks. It is pure and it
/// lives in Core precisely so it is asserted on Linux on every commit: the
/// bundle lookup it feeds only compiles on a Mac, so this is the half that can
/// be proved cheaply and often.
final class LocaleResolutionTests: XCTestCase {

    // MARK: - The ladder

    func testNothingToGoOnIsEnglish() {
        XCTAssertEqual(LocaleResolution.resolve(), "en")
    }

    func testTheMerchantOverrideWins() {
        let language = LocaleResolution.resolve(
            override: "fr", session: "en", device: ["en-US"]
        )
        XCTAssertEqual(language, "fr")
    }

    func testTheSessionWinsOverTheDevice() {
        XCTAssertEqual(LocaleResolution.resolve(session: "fr", device: ["en-US"]), "fr")
    }

    func testTheDeviceDecidesWhenNobodyElseSpeaks() {
        XCTAssertEqual(LocaleResolution.resolve(device: ["fr-FR"]), "fr")
    }

    /// The rung that speaks first decides, and an unsupported answer there is
    /// English — it does not drop through to a rung the merchant did not choose.
    /// Same rule as the hosted checkout page, and it keeps a deliberate
    /// `configure(locale:)` from being overruled by a device setting.
    func testAnUnsupportedOverrideIsEnglishRatherThanTheSessionLanguage() {
        let language = LocaleResolution.resolve(
            override: "de", session: "fr", device: ["fr-FR"]
        )
        XCTAssertEqual(language, "en")
    }

    func testAnUnsupportedSessionLanguageIsEnglishRatherThanTheDeviceLanguage() {
        XCTAssertEqual(LocaleResolution.resolve(session: "de", device: ["fr-FR"]), "en")
    }

    /// An empty string is not an answer. A merchant reading their own config
    /// into `locale:` should get the session's language, not English.
    func testABlankOverrideIsNoOverride() {
        XCTAssertEqual(LocaleResolution.resolve(override: "  ", session: "fr"), "fr")
    }

    func testABlankSessionLocaleIsNoAnswer() {
        XCTAssertEqual(LocaleResolution.resolve(session: "", device: ["fr"]), "fr")
    }

    // MARK: - Matching one tag

    func testAnExactTagMatches() {
        XCTAssertEqual(LocaleResolution.resolve(override: "fr"), "fr")
    }

    func testARegionalTagMatchesOnItsPrimarySubtag() {
        XCTAssertEqual(LocaleResolution.resolve(override: "fr-CA"), "fr")
    }

    func testAScriptAndRegionTagMatchesOnItsPrimarySubtag() {
        XCTAssertEqual(LocaleResolution.resolve(override: "fr-Latn-CA"), "fr")
    }

    /// `Locale.identifier` and server payloads both hand out POSIX-style tags.
    func testAnUnderscoreSeparatorIsAccepted() {
        XCTAssertEqual(LocaleResolution.resolve(override: "fr_CA"), "fr")
    }

    func testMatchingIgnoresCase() {
        XCTAssertEqual(LocaleResolution.resolve(override: "FR-ca"), "fr")
    }

    func testTheResolvedLanguageIsAlwaysLowercased() {
        XCTAssertEqual(LocaleResolution.resolve(override: "EN"), "en")
    }

    // MARK: - Malformed input never throws

    func testAMalformedTagIsEnglish() {
        for tag in ["", "   ", "-", "---", "!!", "-fr", "123"] {
            XCTAssertEqual(
                LocaleResolution.resolve(override: tag, session: "fr"),
                tag.trimmingCharacters(in: .whitespaces).isEmpty ? "fr" : "en",
                "\(tag.debugDescription) should resolve without throwing"
            )
        }
    }

    // MARK: - The device rung is one ranked answer

    /// A preference list is the shopper's single ranked answer, not a ladder of
    /// separate sources, so an entry the SDK cannot speak is skipped rather than
    /// ending the search. A device that prefers German then French gets French.
    func testTheDeviceListIsScannedInOrder() {
        XCTAssertEqual(LocaleResolution.resolve(device: ["de-DE", "fr-FR", "en"]), "fr")
    }

    /// Each candidate is tried exact-then-subtag before the next one is looked
    /// at. Sweeping the whole list for exact matches first would hand a shopper
    /// who ranked Canadian French above English the English sheet.
    func testARegionalPreferenceBeatsALaterExactMatch() {
        XCTAssertEqual(LocaleResolution.resolve(device: ["fr-CA", "en"]), "fr")
    }

    func testADeviceThatSpeaksNothingWeShipIsEnglish() {
        XCTAssertEqual(LocaleResolution.resolve(device: ["de-DE", "ja-JP"]), "en")
    }

    func testADeviceListOfBlanksIsEnglish() {
        XCTAssertEqual(LocaleResolution.resolve(device: ["", "  "]), "en")
    }

    // MARK: - What ships

    func testTheSDKShipsEnglishAndFrench() {
        XCTAssertEqual(LocaleResolution.supportedLanguages, ["en", "fr"])
    }

    func testTheDefaultLanguageIsTheOneThePackageDeclares() {
        XCTAssertEqual(LocaleResolution.defaultLanguage, "en")
    }
}
