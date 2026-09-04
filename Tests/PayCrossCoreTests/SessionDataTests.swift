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
    /// digits, the right guess for every scheme but Amex.
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

    /// Sessions snapshotted before the backend shipped `wallets` carry no
    /// block at all, and there are live ones. Decoding must leave both new
    /// fields nil rather than defaulting them to something the gate reads.
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

    /// A member the server sent as null is not the same as one it omitted,
    /// and neither is the same as `false`. All three have to survive decode
    /// distinctly, because the gate treats only the explicit `false` as a no.
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

    /// A boolean rendered as a string still means what it says.
    ///
    /// The consequence of throwing instead is inverted, not merely absent: the
    /// whole session decode fails, the sheet swallows it, session data becomes
    /// nil, and the strict-false gate reads nil as permission. A merchant who
    /// switched Apple Pay off would get the button.
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

    /// A value no coercion recognises costs that one member and nothing else.
    /// The field groups in the same payload are the thing worth protecting:
    /// losing them renders a card form the server never asked for.
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

    /// A `wallets` value that is not an object at all drops the block and
    /// leaves the rest of the session standing.
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

    /// `account_funding` coerces exactly the way a wallet member does. It no
    /// longer decides the button -- it marks the session as an account-funding
    /// transfer, which a wallet may pay -- but the flag still has to decode,
    /// because the backend keeps writing it and a future client may read it
    /// again.
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
}
