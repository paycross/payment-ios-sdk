#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class LocalizedTests: XCTestCase {

    override func tearDown() {
        SheetLanguage.reset()
        super.tearDown()
    }

    // MARK: - The strings ship with us

    func testEnglishStringsShipInTheSDKBundle() {
        XCTAssertNotNil(sdkBundle.url(forResource: "en", withExtension: "lproj"), "en.lproj missing from the SDK bundle")
    }

    func testFrenchStringsShipInTheSDKBundle() {
        XCTAssertNotNil(sdkBundle.url(forResource: "fr", withExtension: "lproj"), "fr.lproj missing from the SDK bundle")
    }

    func testKeysResolveFromTheSDKBundleNotTheFallback() {
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
    }

    func testMerchantBundleOverridesTheSDKString() {
        XCTAssertEqual(L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer")
    }

    func testTheRemovalKeysResolveFromTheSDKBundle() {
        for key in [
            "paycross_remove_card",
            "paycross_remove_card_title",
            "paycross_remove_card_message",
            "paycross_remove_card_confirm",
            "paycross_remove_card_failed",
            "paycross_session_expired"
        ] {
            XCTAssertNotEqual(L(key, "MISSING"), "MISSING", "\(key) is not in the strings file")
        }
    }

    func testTheRemoveCardLabelKeepsItsPlaceholder() {
        XCTAssertEqual(
            L("paycross_remove_card", "MISSING", "Visa •••• 1111"),
            "Remove card, Visa •••• 1111"
        )
    }

    func testUnknownKeyFallsBackToTheEnglishLiteral() {
        XCTAssertEqual(L("paycross_no_such_key", "Fallback"), "Fallback")
    }

    // MARK: - The two files say the same things

    func testEveryKeyExistsInBothLanguages() throws {
        let english = try keys(in: "en")
        let french = try keys(in: "fr")

        XCTAssertEqual(
            english.subtracting(french), [], "keys in English that French is missing"
        )
        XCTAssertEqual(
            french.subtracting(english), [], "keys in French that English is missing"
        )
    }

    func testBothFilesCarryEveryKeyTheSheetUses() throws {
        XCTAssertEqual(try keys(in: "en").count, 34)
        XCTAssertEqual(try keys(in: "fr").count, 34)
    }

    func testEveryKeyIsPrefixed() throws {
        for key in try keys(in: "en").union(keys(in: "fr")) {
            XCTAssertTrue(key.hasPrefix("paycross_"), "\(key) is not prefixed paycross_")
        }
    }

    func testATranslationNeverDropsItsPlaceholder() throws {
        let english = try values(in: "en")
        let french = try values(in: "fr")

        for (key, value) in english where value.contains("%@") {
            XCTAssertEqual(
                french[key]?.contains("%@"), true,
                "the French \(key) lost its %@"
            )
        }
        for (key, value) in french where value.contains("%@") {
            XCTAssertEqual(
                english[key]?.contains("%@"), true,
                "the English \(key) lost its %@"
            )
        }
    }

    func testThePlaceholderKeysAreTheOnesWeExpect() throws {
        let carrying = try values(in: "en").filter { $0.value.contains("%@") }.keys
        XCTAssertEqual(Set(carrying), [
            "paycross_pay_amount",
            "paycross_remove_card",
            "paycross_remove_card_message",
            "paycross_error_apple_pay_presentation",
            "paycross_field_required",
            "paycross_field_required_accessibility",
            "paycross_field_invalid",
            "paycross_field_max_length"
        ])
    }

    func testATranslationKeepsAsManyPlaceholdersAsTheEnglishHas() throws {
        let english = try values(in: "en")
        let french = try values(in: "fr")

        for (key, value) in english {
            XCTAssertEqual(
                french[key]?.components(separatedBy: "%@").count,
                value.components(separatedBy: "%@").count,
                "the French \(key) carries a different number of placeholders"
            )
        }
    }

    func testTheLengthMessageNamesTheFieldAndTheLimitInBothLanguages() {
        XCTAssertEqual(
            Template.fill(L("paycross_field_max_length", "MISSING"), with: "Notes", "254"),
            "Notes must be 254 characters or fewer"
        )
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            Template.fill(L("paycross_field_max_length", "MISSING"), with: "Remarques", "254"),
            "Champ trop long : Remarques (254 caractères maximum)"
        )
    }

    // MARK: - The installed language is what the sheet reads

    func testInstallingFrenchChangesWhatTheSheetSays() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Numéro de carte")
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
        XCTAssertEqual(L("paycross_save_this_card", "MISSING"), "Enregistrer la carte pour une utilisation future")
    }

    func testInstallingEnglishPutsItBack() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        SheetLanguage.install(LocaleResolution.resolve(override: "en"))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
    }

    func testAnUnshippedLanguageStillReads() {
        SheetLanguage.install(ResolvedLocale(language: "de", formattingTag: "de-DE"))
        XCTAssertNotEqual(L("paycross_card_number", "MISSING"), "MISSING")
    }

    func testInstallingKeepsTheLanguageAndTheFormattingApart() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(SheetLanguage.tag, "fr")
        XCTAssertEqual(SheetLanguage.locale.identifier, "fr")
    }

    func testTheEnglishSheetDoesNotReadTheMerchantsFrench() {
        SheetLanguage.reset()
        XCTAssertEqual(
            L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer"
        )
    }

    func testADeviceOnlySheetFormatsWithTheDevicesOwnLocale() {
        SheetLanguage.install(LocaleResolution.resolve(device: ["de-DE"]))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
        XCTAssertEqual(SheetLanguage.tag, "en")
        XCTAssertEqual(SheetLanguage.locale, .current)
    }

    func testASwissFrenchSessionKeepsItsRegionForTheAmount() {
        SheetLanguage.install(LocaleResolution.resolve(session: "fr-CH"))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Numéro de carte")
        XCTAssertEqual(SheetLanguage.locale.identifier, "fr-CH")
    }

    func testAnAskedForTagWeShipNoWordsForStillFormatsTheAmount() {
        SheetLanguage.install(LocaleResolution.resolve(override: "de-AT"))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
        XCTAssertEqual(SheetLanguage.locale.identifier, "de-AT")
    }

    func testResetHandsTheChoiceBackToFoundation() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr-CH"))
        SheetLanguage.reset()
        XCTAssertEqual(SheetLanguage.tag, "en")
        XCTAssertEqual(SheetLanguage.locale, .current)
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
    }

    // MARK: - The ladder, end to end

    func testTheMerchantOverrideDecidesWhatTheSheetSays() {
        SheetLanguage.install(LocaleResolution.resolve(
            override: "fr", session: "en", device: ["en-US"]
        ))
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
    }

    func testTheSessionDecidesWhenTheMerchantDidNot() {
        SheetLanguage.install(LocaleResolution.resolve(
            session: "fr-CA", device: ["en-US"]
        ))
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
    }

    func testTheDeviceDecidesWhenNobodyElseDid() {
        SheetLanguage.install(LocaleResolution.resolve(device: ["fr-FR", "en-US"]))
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
    }

    func testAnUnsupportedOverrideFallsThroughToTheSession() {
        SheetLanguage.install(LocaleResolution.resolve(override: "de", session: "fr"))
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
    }

    func testAMerchantOverrideStillWinsUnderFrench() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            L("paycross_cancel", "MISSING", merchant: Bundle.module), "Annuler",
            "a key the merchant did not override still comes from us, in French"
        )
    }

    func testAMerchantOverrideComesOutInTheSheetsLanguageNotTheDevices() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            L("paycross_card_number", "MISSING", merchant: Bundle.module),
            "Numéro de la carte bancaire"
        )
    }

    func testAMerchantOverrideComesOutInEnglishUnderAnEnglishSheet() {
        SheetLanguage.install(LocaleResolution.resolve(override: "en"))
        XCTAssertEqual(
            L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer"
        )
    }

    func testAnOverrideWithoutTheSheetsLanguageFallsBackToTheMerchantsOwnPick() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle, merchant: Bundle.module),
            "%d wird nicht mehr angeboten."
        )
    }

    // MARK: - The delete confirmation names its card

    func testTheDeleteConfirmationNamesTheCard() {
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")

        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle),
            "Visa •••• 1111 will no longer be offered for future payments."
        )

        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle),
            "La carte Visa •••• 1111 ne sera plus proposée pour vos prochains paiements."
        )
    }

    // MARK: - A merchant override is a string the SDK does not own

    func testAnOverrideWithTheWrongPlaceholderIsNotTreatedAsAFormatString() {
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle, merchant: Bundle.module),
            "%d wird nicht mehr angeboten."
        )
    }

    func testAnOverrideWithTheWrongPlaceholderSurvivesInFrenchToo() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle, merchant: Bundle.module),
            "%d wird nicht mehr angeboten."
        )
    }

    func testAnOverrideThatKeepsItsPlaceholderIsStillFilled() {
        XCTAssertEqual(
            L("paycross_no_such_key", "Remove card, %@", "Visa •••• 1111"),
            "Remove card, Visa •••• 1111"
        )
    }

    func testEveryPlaceholderKeyFillsInBothLanguages() throws {
        for language in ["en", "fr"] {
            SheetLanguage.install(ResolvedLocale(language: language, formattingTag: language))
            for (key, value) in try values(in: language).filter({ $0.value.contains("%@") }) {
                let placeholders = value.components(separatedBy: "%@").count - 1
                let filled = placeholders > 1
                    ? Template.fill(L(key, "MISSING"), with: "SUBSTITUTED", "ALSO")
                    : L(key, "MISSING", "SUBSTITUTED")
                XCTAssertTrue(
                    filled.contains("SUBSTITUTED"),
                    "\(language) \(key) did not fill its placeholder: \(filled)"
                )
                XCTAssertEqual(
                    placeholders > 1, filled.contains("ALSO"),
                    "\(language) \(key) did not fill its second placeholder: \(filled)"
                )
                XCTAssertFalse(
                    filled.contains("%@"), "\(language) \(key) kept a %@ after filling"
                )
            }
        }
    }

    // MARK: - Reading a .lproj off the bundle

    private func keys(in language: String) throws -> Set<String> {
        Set(try values(in: language).keys)
    }

    private func values(in language: String) throws -> [String: String] {
        let lproj = try XCTUnwrap(
            sdkBundle.path(forResource: language, ofType: "lproj"),
            "\(language).lproj is not in the SDK bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: lproj))
        let file = try XCTUnwrap(
            bundle.path(forResource: "Localizable", ofType: "strings"),
            "\(language).lproj has no Localizable.strings"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: file) as? [String: String])
    }
}
#endif
