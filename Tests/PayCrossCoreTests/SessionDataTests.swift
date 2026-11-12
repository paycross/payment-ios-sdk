import XCTest
@testable import PayCrossCore

final class SessionDataTests: XCTestCase {

    private let payload = """
    {
      "session_id": "sess_1",
      "status": "open",
      "latest_transaction_id": "txn_9",
      "data": {
        "locale": "en-GB",
        "return_url": "https://merchant.example.com/return",
        "merchant_country": "GB",
        "save_card_config": { "usage": "card_on_file" },
        "saved_cards": [
          {
            "uuid": "card_1",
            "masked_pan": "411111******1111",
            "card_brand": "VISA",
            "expire_month": "12",
            "expire_year": "2030",
            "cardholder_name": "A PERSON"
          }
        ],
        "field_groups": [
          {
            "key": "billing",
            "label": "Billing address",
            "fields": [
              {
                "name": "postcode",
                "type": "text",
                "label": "Postcode",
                "required": true,
                "validation": { "pattern": "^[A-Z0-9 ]+$", "max_length": 8 }
              },
              {
                "name": "state",
                "type": "select",
                "condition": { "when": "country", "in": ["US", "CA"], "display": "show" },
                "options": [{ "value": "NY", "label": "New York" }]
              }
            ]
          }
        ]
      }
    }
    """

    func testFullSessionDecodes() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(session.sessionID, "sess_1")
        XCTAssertEqual(session.latestTransactionID, "txn_9")

        let data = try XCTUnwrap(session.data)
        XCTAssertEqual(data.locale, "en-GB")
        XCTAssertEqual(data.merchantCountry, "GB")
        XCTAssertTrue(data.allowsSavingCard)
        XCTAssertEqual(data.saveCardConfig?.usage, "card_on_file")
    }

    // MARK: - locale

    func testTheSessionLanguageDecodes() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(try XCTUnwrap(session.data).locale, "en-GB")
    }

    func testAMissingLocaleIsNilRatherThanADecodingFailure() throws {
        let json = #"{"session_id":"s","status":"open","data":{"merchant_country":"GB"}}"#
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertNil(try XCTUnwrap(session.data).locale)
    }

    func testAMalformedLocalePassesThroughAsAString() throws {
        for tag in ["", "not a locale", "fr_CA", "FR", "zz-ZZ-ZZ"] {
            let json = #"{"session_id":"s","status":"open","data":{"locale":"\#(tag)"}}"#
            let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
            XCTAssertEqual(try XCTUnwrap(session.data).locale, tag)
        }
    }

    func testSavedCardMapsToThePresentationType() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        let card = try XCTUnwrap(session.data?.savedCards?.first).presentable

        XCTAssertEqual(card.id, "card_1")
        XCTAssertEqual(card.brand, .visa)
        XCTAssertEqual(card.last4, "1111", "masked PANs contain asterisks; only digits count")
        XCTAssertEqual(card.expiryLabel, "12/30")
    }

    func testBrandStringsAreMappedLeniently() {
        XCTAssertEqual(WireSavedCard.brand(from: "VISA"), .visa)
        XCTAssertEqual(WireSavedCard.brand(from: "visa"), .visa)
        XCTAssertEqual(WireSavedCard.brand(from: "MasterCard"), .mastercard)
        XCTAssertEqual(WireSavedCard.brand(from: "master card"), .mastercard)
        XCTAssertEqual(WireSavedCard.brand(from: "American Express"), .amex)
        XCTAssertEqual(WireSavedCard.brand(from: "amex"), .amex)
    }

    func testUnknownBrandFallsBackRatherThanFailing() {
        XCTAssertEqual(WireSavedCard.brand(from: "Diners Club"), .unknown)

        let card = WireSavedCard(
            uuid: "c", maskedPAN: "3600******1234", cardBrand: nil,
            expireMonth: "01", expireYear: "2028", cardholderName: "X"
        ).presentable
        XCTAssertEqual(card.brand, .unknown)
        XCTAssertEqual(card.brand.cvvLength, 3)
    }

    func testFieldGroupsDecodeIncludingConditionsAndValidation() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        let group = try XCTUnwrap(session.data?.fieldGroups?.first)

        XCTAssertEqual(group.key, "billing")
        XCTAssertEqual(group.fields?.count, 2)

        let postcode = try XCTUnwrap(group.fields?.first)
        XCTAssertEqual(postcode.required, true)
        XCTAssertEqual(postcode.validation?.maxLength, 8)
        XCTAssertEqual(postcode.validation?.pattern, "^[A-Z0-9 ]+$")

        let state = try XCTUnwrap(group.fields?.last)
        XCTAssertEqual(state.condition?.whenField, "country")
        XCTAssertEqual(state.condition?.whenIn, ["US", "CA"])
        XCTAssertEqual(state.options?.first?.value, "NY")
    }

    // MARK: - Opt-in groups

    private let optInPayload = """
    {
      "session_id": "sess_2",
      "data": {
        "field_groups": [
          {
            "key": "billing_address",
            "label": "Billing Address",
            "fields": [{ "name": "line1", "label": "Address line 1", "required": true }]
          },
          {
            "key": "shipping_address",
            "label": "Shipping Address",
            "labels": { "en": "Shipping Address", "fr": "Adresse de livraison" },
            "opt_in": true,
            "fields": [{ "name": "line1", "label": "Address line 1", "required": true }]
          }
        ]
      }
    }
    """

    private func groups(in json: String) throws -> [FieldGroup] {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(session.data?.fieldGroups)
    }

    func testTheOptInFlagDecodesOnTheGroupThatCarriesIt() throws {
        let decoded = try groups(in: optInPayload)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.last?.optIn, true)
        XCTAssertEqual(decoded.last?.isOptIn, true)
        XCTAssertEqual(decoded.last?.label(in: "fr"), "Adresse de livraison")
    }

    func testAGroupWithoutTheFlagDecodesAsMandatory() throws {
        XCTAssertNil(try groups(in: optInPayload).first?.optIn)
        XCTAssertEqual(try groups(in: optInPayload).first?.isOptIn, false)
        XCTAssertEqual(try groups(in: payload).first?.isOptIn, false)
    }

    func testTheFlagIsReadWhicheverWayTheServerSpelledIt() throws {
        for spelling in ["true", "\"true\"", "1"] {
            let json = optInPayload.replacingOccurrences(
                of: "\"opt_in\": true", with: "\"opt_in\": \(spelling)"
            )
            XCTAssertEqual(
                try groups(in: json).last?.isOptIn, true, "opt_in: \(spelling) was not read"
            )
        }
        for spelling in ["false", "\"false\"", "0", "null"] {
            let json = optInPayload.replacingOccurrences(
                of: "\"opt_in\": true", with: "\"opt_in\": \(spelling)"
            )
            XCTAssertEqual(
                try groups(in: json).last?.isOptIn, false, "opt_in: \(spelling) was read as yes"
            )
        }
    }

    func testAnUnreadableFlagCostsTheFlagRatherThanTheWholeForm() throws {
        let json = optInPayload.replacingOccurrences(
            of: "\"opt_in\": true", with: "\"opt_in\": { \"who\": \"knows\" }"
        )
        let decoded = try groups(in: json)
        XCTAssertEqual(decoded.count, 2, "the whole form was lost with the flag")
        XCTAssertEqual(
            decoded.last?.isOptIn, false,
            "an unreadable flag must leave the group mandatory, which a shopper can still pay through"
        )
        XCTAssertEqual(decoded.last?.fields?.count, 1)
    }

    func testAGroupRoundTripsThroughItsOwnEncoding() throws {
        let original = try XCTUnwrap(try groups(in: optInPayload).last)
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(FieldGroup.self, from: encoded), original)
    }

    // MARK: - Per-language labels

    private let bilingualPayload = """
    {
      "session_id": "sess_1",
      "status": "open",
      "data": {
        "field_groups": [
          {
            "key": "billing",
            "label": "Billing address",
            "labels": { "en": "Billing address", "fr": "Adresse de facturation" },
            "fields": [
              {
                "name": "email",
                "type": "email",
                "label": "Email address",
                "labels": { "en": "Email address", "fr": "Adresse e-mail" },
                "placeholder": "email@example.com",
                "placeholders": { "en": "email@example.com", "fr": "email@example.com" },
                "required": true,
                "validation": {
                  "max_length": 254,
                  "messages": { "required": "This field is required" },
                  "messages_i18n": {
                    "en": { "required": "This field is required" },
                    "fr": { "required": "Ce champ est obligatoire" }
                  }
                }
              },
              {
                "name": "state",
                "type": "select",
                "options": [
                  { "value": "NY", "label": "New York",
                    "labels": { "en": "New York", "fr": "État de New York" } }
                ]
              }
            ]
          }
        ]
      }
    }
    """

    func testTheLanguageMapsDecode() throws {
        let session = try JSONDecoder().decode(
            SessionResponse.self, from: Data(bilingualPayload.utf8)
        )
        let group = try XCTUnwrap(session.data?.fieldGroups?.first)
        let email = try XCTUnwrap(group.fields?.first)
        let option = try XCTUnwrap(group.fields?.last?.options?.first)

        XCTAssertEqual(group.labels?["fr"], "Adresse de facturation")
        XCTAssertEqual(email.labels?["fr"], "Adresse e-mail")
        XCTAssertEqual(email.placeholders?["fr"], "email@example.com")
        XCTAssertEqual(option.labels?["fr"], "État de New York")
        XCTAssertEqual(email.validation?.messagesI18n?["fr"]?["required"], "Ce champ est obligatoire")
        XCTAssertEqual(email.validation?.messagesI18n?["en"]?["required"], "This field is required")
    }

    func testTheMapsAreReadByLanguageAndTheSingularKeysStillHoldTheirValues() throws {
        let session = try JSONDecoder().decode(
            SessionResponse.self, from: Data(bilingualPayload.utf8)
        )
        let group = try XCTUnwrap(session.data?.fieldGroups?.first)
        let email = try XCTUnwrap(group.fields?.first)
        let option = try XCTUnwrap(group.fields?.last?.options?.first)

        XCTAssertEqual(group.label(in: "fr"), "Adresse de facturation")
        XCTAssertEqual(group.label(in: "en"), "Billing address")
        XCTAssertEqual(group.label, "Billing address", "the singular key keeps its value")
        XCTAssertEqual(email.label(in: "fr"), "Adresse e-mail")
        XCTAssertEqual(email.placeholder(in: "fr"), "email@example.com")
        XCTAssertEqual(option.label(in: "fr"), "État de New York")
        XCTAssertEqual(email.validation?.message("required", in: "fr"), "Ce champ est obligatoire")
    }

    func testAnUnnamedLanguageOrRuleFallsBackToTheSingularValue() throws {
        let session = try JSONDecoder().decode(
            SessionResponse.self, from: Data(bilingualPayload.utf8)
        )
        let email = try XCTUnwrap(session.data?.fieldGroups?.first?.fields?.first)

        XCTAssertEqual(email.label(in: "de"), "Email address")
        XCTAssertEqual(email.placeholder(in: "de"), "email@example.com")
        XCTAssertEqual(email.validation?.message("required", in: "de"), "This field is required")
        XCTAssertNil(email.validation?.message("pattern", in: "fr"))
    }

    func testASessionWithoutTheMapsStillDecodesAndReads() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        let group = try XCTUnwrap(session.data?.fieldGroups?.first)
        let postcode = try XCTUnwrap(group.fields?.first)
        let option = try XCTUnwrap(group.fields?.last?.options?.first)

        XCTAssertNil(group.labels)
        XCTAssertNil(postcode.labels)
        XCTAssertNil(postcode.placeholders)
        XCTAssertNil(option.labels)
        XCTAssertNil(postcode.validation?.messagesI18n)

        XCTAssertEqual(group.label(in: "fr"), "Billing address")
        XCTAssertEqual(postcode.label(in: "fr"), "Postcode")
        XCTAssertNil(postcode.placeholder(in: "fr"), "this field never had a placeholder")
        XCTAssertEqual(option.label(in: "fr"), "New York")
    }

    func testARuleMissingFromItsLanguagesMapFallsBackToTheSingularSentence() {
        let validation = FieldValidation(
            messages: ["required": "This field is required", "pattern": "Wrong format"],
            messagesI18n: ["fr": ["required": "Ce champ est obligatoire"]]
        )

        XCTAssertEqual(validation.message("required", in: "fr"), "Ce champ est obligatoire")
        XCTAssertEqual(validation.message("pattern", in: "fr"), "Wrong format")
    }

    func testAFieldWithNoPlaceholderReadsAsNilInEveryLanguage() throws {
        let field = FieldDefinition(
            name: "postcode",
            label: "Postcode",
            labels: ["en": "Postcode", "fr": "Code postal"]
        )
        XCTAssertNil(field.placeholder(in: "fr"))
        XCTAssertNil(field.placeholder(in: nil))
        XCTAssertEqual(field.label(in: "fr"), "Code postal")
    }

    func testANilLanguageReadsTheSingularValue() throws {
        let session = try JSONDecoder().decode(
            SessionResponse.self, from: Data(bilingualPayload.utf8)
        )
        let group = try XCTUnwrap(session.data?.fieldGroups?.first)
        let email = try XCTUnwrap(group.fields?.first)

        XCTAssertEqual(group.label(in: nil), "Billing address")
        XCTAssertEqual(email.label(in: nil), "Email address")
        XCTAssertEqual(email.validation?.message("required", in: nil), "This field is required")
    }

    func testMinimalSessionDecodes() throws {
        let json = #"{"session_id":"s"}"#
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))

        XCTAssertEqual(session.sessionID, "s")
        XCTAssertNil(session.data)
    }

    func testSessionWithEmptyDataOffersNoSaving() throws {
        let json = #"{"session_id":"s","data":{}}"#
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))

        XCTAssertFalse(
            try XCTUnwrap(session.data).allowsSavingCard,
            "the save checkbox appears only when the server configured it"
        )
        XCTAssertNil(session.data?.savedCards)
    }

    // MARK: - saved_cards_config

    func testSavedCardsConfigDecodes() throws {
        let json = """
        { "session_id": "s", "data": {
            "saved_cards_config": { "allow_removal": true, "preselect": true } } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertTrue(data.allowsSavedCardRemoval)
        XCTAssertTrue(data.preselectsSavedCard)
    }

    func testSavedCardsConfigDefaultsToOffWhenTheBlockIsAbsent() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        let data = try XCTUnwrap(session.data)

        XCTAssertNil(data.savedCardsConfig)
        XCTAssertFalse(data.allowsSavedCardRemoval)
        XCTAssertFalse(data.preselectsSavedCard)
        XCTAssertEqual(data.savedCards?.count, 1, "the cards themselves still decode")
    }

    func testAPartialSavedCardsConfigLeavesTheOtherFlagOff() throws {
        let json = #"{"session_id":"s","data":{"saved_cards_config":{"allow_removal":true}}}"#
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertTrue(data.allowsSavedCardRemoval)
        XCTAssertFalse(data.preselectsSavedCard)
    }

    func testSavedCardsConfigFlagsCoerceFromStringsAndNumbers() throws {
        let json = """
        { "session_id": "s", "data": {
            "saved_cards_config": { "allow_removal": "true", "preselect": 0 } } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertTrue(data.allowsSavedCardRemoval)
        XCTAssertFalse(data.preselectsSavedCard)
    }

    func testAMalformedSavedCardsConfigDoesNotLoseTheSession() throws {
        let json = """
        { "session_id": "s", "data": {
            "saved_cards_config": "yes",
            "saved_cards": [{
              "uuid": "card_1", "masked_pan": "411111******1111", "card_brand": "VISA",
              "expire_month": "12", "expire_year": "2030", "cardholder_name": "A PERSON"
            }] } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertNil(data.savedCardsConfig)
        XCTAssertFalse(data.allowsSavedCardRemoval)
        XCTAssertEqual(data.savedCards?.count, 1)
    }

    func testASnapshotWithoutAWalletBlockDecodes() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        let data = try XCTUnwrap(session.data)

        XCTAssertNil(data.wallets)
        XCTAssertNil(data.accountFunding)
    }

    func testWalletAvailabilityDecodes() throws {
        let json = """
        { "session_id": "sess_1", "data": {
            "wallets": { "apple_pay": true, "google_pay": false },
            "account_funding": false } }
        """
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        let data = try XCTUnwrap(session.data)

        XCTAssertEqual(data.wallets?.applePay, true)
        XCTAssertEqual(data.wallets?.googlePay, false)
        XCTAssertEqual(data.accountFunding, false)
    }

    func testANullWalletMemberDecodesAsNilRatherThanFalse() throws {
        let json = """
        { "session_id": "sess_1", "data": { "wallets": { "apple_pay": null } } }
        """
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        let data = try XCTUnwrap(session.data)

        XCTAssertNotNil(data.wallets)
        XCTAssertNil(data.wallets?.applePay)
    }

    func testAccountFundingDecodes() throws {
        let json = """
        { "session_id": "sess_1", "data": { "account_funding": true } }
        """
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))

        XCTAssertEqual(session.data?.accountFunding, true)
    }

    // MARK: - Wallet flags the backend spelled in another type

    func testAWalletMemberSentAsAStringCoercesToBool() throws {
        let off = try JSONDecoder().decode(
            SessionResponse.self,
            from: Data(#"{"session_id":"s","data":{"wallets":{"apple_pay":"false"}}}"#.utf8)
        )
        XCTAssertEqual(off.data?.wallets?.applePay, false)
        XCTAssertFalse(WalletGate.allowsApplePay(off.data), "a string false is still a refusal")

        let on = try JSONDecoder().decode(
            SessionResponse.self,
            from: Data(#"{"session_id":"s","data":{"wallets":{"apple_pay":"true"}}}"#.utf8)
        )
        XCTAssertEqual(on.data?.wallets?.applePay, true)
    }

    func testAWalletMemberSentAsANumberCoercesToBool() throws {
        let off = try JSONDecoder().decode(
            SessionResponse.self,
            from: Data(#"{"session_id":"s","data":{"wallets":{"apple_pay":0}}}"#.utf8)
        )
        XCTAssertEqual(off.data?.wallets?.applePay, false)
        XCTAssertFalse(WalletGate.allowsApplePay(off.data), "zero is still a refusal")

        let on = try JSONDecoder().decode(
            SessionResponse.self,
            from: Data(#"{"session_id":"s","data":{"wallets":{"apple_pay":1}}}"#.utf8)
        )
        XCTAssertEqual(on.data?.wallets?.applePay, true)
    }

    func testAnUnrecognisedWalletMemberDecodesAsNilWithoutLosingTheSession() throws {
        let json = """
        { "session_id": "s", "data": {
            "wallets": { "apple_pay": "maybe", "google_pay": 7 },
            "field_groups": [{ "key": "billing" }] } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertNotNil(data.wallets, "the block itself parsed")
        XCTAssertNil(data.wallets?.applePay)
        XCTAssertNil(data.wallets?.googlePay)
        XCTAssertEqual(data.fieldGroups?.first?.key, "billing")
        XCTAssertTrue(WalletGate.allowsApplePay(data), "an unreadable flag is not a refusal")
    }

    func testAMalformedWalletsBlockDecodesAsNilWithoutLosingTheSession() throws {
        let json = """
        { "session_id": "s", "data": {
            "wallets": [],
            "field_groups": [{ "key": "billing" }] } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertNil(data.wallets)
        XCTAssertEqual(data.fieldGroups?.first?.key, "billing")
        XCTAssertTrue(WalletGate.allowsApplePay(data))
    }

    func testAccountFundingCoercesFromAString() throws {
        let json = """
        { "session_id": "s", "data": {
            "wallets": { "apple_pay": true },
            "account_funding": "true",
            "field_groups": [{ "key": "billing" }] } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertEqual(data.accountFunding, true)
        XCTAssertEqual(data.fieldGroups?.first?.key, "billing")
        XCTAssertTrue(WalletGate.allowsApplePay(data))
    }

    // MARK: - Branding

    func testBrandColorDecodesFromTheBrandingBlock() throws {
        let json = ##"{"session_id":"s","data":{"branding":{"brand_color":"#1E88E5"}}}"##
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertEqual(data.branding?.brandColor, "#1E88E5")
    }

    func testBrandingIsNilWhenTheBlockIsAbsent() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Data(payload.utf8))
        XCTAssertNil(try XCTUnwrap(session.data).branding)
    }

    func testAMalformedBrandingBlockDoesNotLoseTheSession() throws {
        let json = """
        { "session_id": "s", "data": {
            "branding": "blue",
            "saved_cards": [{
              "uuid": "card_1", "masked_pan": "411111******1111", "card_brand": "VISA",
              "expire_month": "12", "expire_year": "2030", "cardholder_name": "A PERSON"
            }] } }
        """
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertNil(data.branding)
        XCTAssertEqual(data.savedCards?.count, 1)
    }

    func testAnEmptyBrandingBlockCarriesNoColour() throws {
        let json = #"{"session_id":"s","data":{"branding":{}}}"#
        let data = try XCTUnwrap(
            try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8)).data
        )

        XCTAssertNotNil(data.branding)
        XCTAssertNil(data.branding?.brandColor)
    }
}
