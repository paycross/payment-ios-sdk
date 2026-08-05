import XCTest
@testable import PayCrossCore

/// The checkout API's session resource decides what the form may show: which
/// saved cards, whether saving is offered, which extra fields. Getting this shape
/// wrong means the sheet silently renders less than the server asked for.
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

    /// An unknown brand must not break the sheet; it validates its CVV at three
    /// digits, which is what Android does for every saved card anyway.
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

        // "when" and "in" are Swift keywords on the wire; the CodingKeys must map
        // them or the condition silently decodes as nil and the field always shows.
        let state = try XCTUnwrap(group.fields?.last)
        XCTAssertEqual(state.condition?.whenField, "country")
        XCTAssertEqual(state.condition?.whenIn, ["US", "CA"])
        XCTAssertEqual(state.options?.first?.value, "NY")
    }

    /// A minimal session must not fail to decode: everything under `data` is
    /// optional, and a checkout with no saved cards and no extra fields is normal.
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
}
