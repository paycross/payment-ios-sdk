#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// A `Text("Card Number")` inside a package resolves its key against
/// `Bundle.main` — the merchant's app — so a merchant whose own strings file
/// happens to define one of our labels repaints it. These assert the two halves
/// of the fix: the strings ship with us, and lookups find them there. The last
/// two cover the contract that replaced the accident — a merchant bundle that
/// names one of our keys wins, and a key nobody defines still reads.
///
/// `@MainActor` because `L` is: the language the sheet speaks is main-actor
/// state, installed once per presentation.
@MainActor
final class LocalizedTests: XCTestCase {

    override func tearDown() {
        // Every one of these installs a language; leaving one installed would
        // hand the next test class a sheet in whatever tongue this one ended in.
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
        // The fallback is deliberately wrong: if the key is missing, this fails.
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
    }

    func testMerchantBundleOverridesTheSDKString() {
        // This test target's own bundle defines paycross_card_number, playing
        // the merchant app that wants its own wording for that one label.
        XCTAssertEqual(L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer")
    }

    /// The delete affordance's copy is only reachable under a session that
    /// allows removal, so a key missing from the strings file would ship
    /// unnoticed and read as its own name in the alert.
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

    /// The delete button's label interpolates the row it belongs to, so an
    /// override that drops the `%@` silently unnames every trash on the screen.
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

    /// A key in one file and not the other is the localization bug that ships:
    /// English everywhere in QA, and one raw `paycross_` key in the middle of a
    /// French sheet the day a shopper meets the branch it lives on.
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

    /// The prefix is the whole reason a merchant override is deliberate rather
    /// than accidental, so a key added without one is a collision waiting.
    func testEveryKeyIsPrefixed() throws {
        for key in try keys(in: "en").union(keys(in: "fr")) {
            XCTAssertTrue(key.hasPrefix("paycross_"), "\(key) is not prefixed paycross_")
        }
    }

    /// A translation that drops the placeholder loses the card, the amount or
    /// the field name it was supposed to name.
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

    /// Eight keys carry one. Naming them pins the sheet against a ninth arriving
    /// in one language only.
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

    /// One key carries two, and a translation that keeps only the first passes
    /// every check above while losing the limit the shopper needs. The length
    /// message is the only string the SDK ships with more than one placeholder,
    /// which is exactly why nothing else would have caught it.
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

    /// Filled the way the sheet fills it: the sheet looks the template up and
    /// Core, which ships no strings, puts the two values into it.
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

    /// A language the SDK ships no `.lproj` for is a packaging mistake, not a
    /// reason to crash a checkout. The resolver never hands one over — that is
    /// what the clamp is for — so this stands one in by hand.
    func testAnUnshippedLanguageStillReads() {
        SheetLanguage.install(ResolvedLocale(language: "de", formattingTag: "de-DE"))
        XCTAssertNotEqual(L("paycross_card_number", "MISSING"), "MISSING")
    }

    func testInstallingKeepsTheLanguageAndTheFormattingApart() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(SheetLanguage.tag, "fr")
        XCTAssertEqual(SheetLanguage.locale.identifier, "fr")
    }

    /// The merchant's own French wording must not leak into an English sheet
    /// just because the merchant happens to ship a French `.lproj`.
    func testTheEnglishSheetDoesNotReadTheMerchantsFrench() {
        SheetLanguage.reset()
        XCTAssertEqual(
            L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer"
        )
    }

    /// A device nobody overrode keeps `Locale.current`, region and format
    /// settings and all, which is what the SDK formatted with before it spoke a
    /// second language. Rebuilding a locale from the device's language list
    /// would have quietly rewritten the price for anyone whose Region does not
    /// simply follow their language.
    func testADeviceOnlySheetFormatsWithTheDevicesOwnLocale() {
        SheetLanguage.install(LocaleResolution.resolve(device: ["de-DE"]))
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
        XCTAssertEqual(SheetLanguage.tag, "en")
        XCTAssertEqual(SheetLanguage.locale, .current)
    }

    /// An asked-for tag is used as asked for, so the region survives where the
    /// language drops it.
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

    /// `LocaleResolutionTests` owns the rule on Linux. This is the half that
    /// cannot run there: that the candidate which wins is the one whose words
    /// appear.
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

    /// The change the lead made after the first review: a candidate naming a
    /// language the SDK does not ship is passed over rather than ending the
    /// search, so this sheet is French and not English.
    func testAnUnsupportedOverrideFallsThroughToTheSession() {
        SheetLanguage.install(LocaleResolution.resolve(override: "de", session: "fr"))
        XCTAssertEqual(L("paycross_cancel", "MISSING"), "Annuler")
    }

    /// Decision 3. An explicit locale and a reworded label answer different
    /// questions, so asking for French does not switch a merchant's own wording
    /// off — Adyen's rule, which the spec quoted, does not apply to a lookup
    /// that reads the merchant bundle first whatever happens.
    func testAMerchantOverrideStillWinsUnderFrench() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        XCTAssertEqual(
            L("paycross_cancel", "MISSING", merchant: Bundle.module), "Annuler",
            "a key the merchant did not override still comes from us, in French"
        )
    }

    /// The one a merchant would never predict. `Bundle.localizedString` picks a
    /// localization from the *device's* language list, so asking it directly
    /// hands a French sheet on an English phone the English override: SDK labels
    /// in French and the merchant's reworded ones in English, from the single
    /// call that was supposed to settle the language.
    ///
    /// The simulator these run on is English, and this test bundle plays the
    /// merchant app with a reworded card-number label in both languages. Under a
    /// French sheet the French one has to win.
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

    /// A merchant who ships no `.lproj` for the sheet's language still gets
    /// their override — whatever their own app would have resolved it to. Only
    /// the English half of this bundle names this key.
    func testAnOverrideWithoutTheSheetsLanguageFallsBackToTheMerchantsOwnPick() {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle, merchant: Bundle.module),
            "%d wird nicht mehr angeboten."
        )
    }

    // MARK: - The delete confirmation names its card

    /// The English gained a `%@` this train, where it had none. A call site that
    /// forgets to fill it puts a literal `%@` in front of a shopper about to
    /// delete a card, in both languages.
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

    /// The hazard `Template.fill` exists for, on the one key that gained a
    /// placeholder this train. A merchant who typed `%d` into an override of it
    /// would, under `String(format:)`, have the sheet read an integer vararg
    /// nobody passed — undefined behaviour reached from a text file, on a screen
    /// holding a card number. The alert comes out with the `%d` intact instead.
    func testAnOverrideWithTheWrongPlaceholderIsNotTreatedAsAFormatString() {
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(
            L("paycross_remove_card_message", "MISSING", card.rowTitle, merchant: Bundle.module),
            "%d wird nicht mehr angeboten."
        )
    }

    /// The same override under French, since the alert is reached in both.
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

    /// Every key that carries a `%@` goes through the filling lookup, in both
    /// languages, so none of them can reach a shopper with the placeholder still
    /// in it.
    ///
    /// Each key is filled with as many values as it carries placeholders, which
    /// for all but one of them is one. `paycross_field_max_length` names the
    /// field and the limit and is filled by Core rather than by `L`, so it is
    /// filled here the way Core fills it.
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
