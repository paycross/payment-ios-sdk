import XCTest
@testable import PayCrossCore

/// The Apple Pay submit payload, end to end from a PassKit token to the JSON
/// the edge parses.
///
/// Every assertion here reads encoded JSON rather than the struct that produced
/// it. The failures this card exists to prevent -- a dropped field, an omitted
/// key -- live between the two, and a test that asserts on the struct cannot
/// see them.
final class ApplePayPayloadTests: XCTestCase {

    /// The shape `PKPaymentToken` produces, as the web posts it: `paymentData`
    /// at the top level, which is where the edge looks for the envelope.
    private let tokenJSON = """
    {
      "paymentData": {
        "version": "EC_v1",
        "data": "l6ptDgUVfd9...",
        "signature": "MIAGCSqGSIb3...",
        "header": {
          "ephemeralPublicKey": "MFkwEwYHKoZIzj0CAQ...",
          "publicKeyHash": "AS+1J1234ABCdef=",
          "transactionId": "31323334353637"
        }
      },
      "paymentMethod": {
        "displayName": "Visa 1234",
        "network": "Visa",
        "type": "debit"
      },
      "transactionIdentifier": "31323334353637"
    }
    """

    private func decodedToken() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(tokenJSON.utf8))
    }

    /// Re-encodes a value and reads it back as plain Foundation objects, which
    /// is as close to "what the edge receives" as a unit test gets.
    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    // MARK: - The passthrough

    func testATokenSurvivesTheRoundTripFieldByField() throws {
        let encoded = try encodedObject(decodedToken())

        let paymentData = try XCTUnwrap(encoded["paymentData"] as? [String: Any])
        let header = try XCTUnwrap(paymentData["header"] as? [String: Any])
        XCTAssertEqual(paymentData["version"] as? String, "EC_v1")
        XCTAssertEqual(paymentData["signature"] as? String, "MIAGCSqGSIb3...")
        XCTAssertEqual(header["publicKeyHash"] as? String, "AS+1J1234ABCdef=")
        XCTAssertEqual(header["transactionId"] as? String, "31323334353637")

        let method = try XCTUnwrap(encoded["paymentMethod"] as? [String: Any])
        XCTAssertEqual(method["network"] as? String, "Visa")
        XCTAssertEqual(encoded["transactionIdentifier"] as? String, "31323334353637")
    }

    func testTheKeySetIsUnchanged() throws {
        let encoded = try encodedObject(decodedToken())

        XCTAssertEqual(Set(encoded.keys), ["paymentData", "paymentMethod", "transactionIdentifier"])
    }

    /// An integer must come back an integer. Routing every number through
    /// `Double` turns a large one into exponent notation, and a field the
    /// vault reads as a string comparison would then never match.
    func testAnIntegerIsNotTurnedIntoAFloat() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n": 1234567890123}"#.utf8))
        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(value), encoding: .utf8))

        XCTAssertTrue(encoded.contains("1234567890123"), encoded)
        XCTAssertFalse(encoded.contains("e+"), encoded)
    }

    func testADecimalSurvives() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n": 1.5}"#.utf8))
        let encoded = try encodedObject(value)

        XCTAssertEqual(encoded["n"] as? Double, 1.5)
    }

    /// An explicit null is a value the server sent, not a field to drop.
    func testAnExplicitNullSurvives() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a": null}"#.utf8))
        let encoded = try encodedObject(value)

        XCTAssertTrue(encoded.keys.contains("a"))
        XCTAssertTrue(encoded["a"] is NSNull)
    }

    func testNestedArraysAndBooleansSurvive() throws {
        let json = #"{"a": [1, "two", true, {"b": false}]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let encoded = try encodedObject(value)

        let array = try XCTUnwrap(encoded["a"] as? [Any])
        XCTAssertEqual(array.count, 4)
        XCTAssertEqual(array[1] as? String, "two")
        XCTAssertEqual(array[2] as? Bool, true)
        XCTAssertEqual((array[3] as? [String: Any])?["b"] as? Bool, false)
    }

    func testAnEscapedStringSurvives() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"s": "a\"b\\c\nd"}"#.utf8))
        let encoded = try encodedObject(value)

        XCTAssertEqual(encoded["s"] as? String, "a\"b\\c\nd")
    }

    // MARK: - The submit payload

    private func applePayRequest(
        merchantIdentifier: String = "merchant.pay-cross.com",
        fieldGroups: [String: [String: String]]? = nil
    ) throws -> SubmitCardRequest {
        let token = try XCTUnwrap(
            WalletToken.applePay(data: try decodedToken(), merchantIdentifier: merchantIdentifier)
        )
        return SubmitCardRequest(
            session: "session.jwt.here",
            walletToken: token,
            browserInfo: BrowserInfo(
                userAgent: "PayCrossSDK-iOS/0.2.0",
                screenWidth: 1170,
                screenHeight: 2532,
                timezoneOffset: 0,
                language: "en-GB"
            ),
            fieldGroups: fieldGroups
        )
    }

    func testThePaymentMethodIsApplePay() throws {
        let encoded = try encodedObject(try applePayRequest())

        XCTAssertEqual(encoded["payment_method"] as? String, "apple_pay")
    }

    /// The card key must be absent, not null: `validatePaymentMethod` on the
    /// edge branches on the payment method and a stray card object on a wallet
    /// body is a contradiction nobody downstream has to resolve.
    func testNoCardObjectIsSent() throws {
        let encoded = try encodedObject(try applePayRequest())

        XCTAssertFalse(encoded.keys.contains("card"))
    }

    func testTheWalletTokenTypeMatchesThePaymentMethod() throws {
        let encoded = try encodedObject(try applePayRequest())
        let wallet = try XCTUnwrap(encoded["wallet_token"] as? [String: Any])

        // The edge refuses a body whose wallet_token.type differs from its
        // payment_method, so these two are one decision, not two.
        XCTAssertEqual(wallet["type"] as? String, "apple_pay")
        XCTAssertEqual(wallet["type"] as? String, encoded["payment_method"] as? String)
    }

    /// The assertion this whole card exists for. An omitted merchant
    /// identifier is not refused anywhere: it reads to the edge as a web
    /// token, the vault derives the environment default key, and the shopper
    /// gets a generic decline.
    func testTheMerchantIdentifierIsAlwaysPresentAndNonEmpty() throws {
        let encoded = try encodedObject(try applePayRequest())
        let wallet = try XCTUnwrap(encoded["wallet_token"] as? [String: Any])

        XCTAssertTrue(wallet.keys.contains("merchant_identifier"))
        let identifier = try XCTUnwrap(wallet["merchant_identifier"] as? String)
        XCTAssertEqual(identifier, "merchant.pay-cross.com")
        XCTAssertFalse(identifier.isEmpty)
    }

    func testAnEmptyIdentifierCannotBuildAToken() throws {
        XCTAssertNil(WalletToken.applePay(data: try decodedToken(), merchantIdentifier: ""))
    }

    func testTheTokenBodyIsCarriedVerbatim() throws {
        let encoded = try encodedObject(try applePayRequest())
        let wallet = try XCTUnwrap(encoded["wallet_token"] as? [String: Any])
        let data = try XCTUnwrap(wallet["data"] as? [String: Any])
        let paymentData = try XCTUnwrap(data["paymentData"] as? [String: Any])

        XCTAssertEqual(paymentData["version"] as? String, "EC_v1")
        XCTAssertEqual(
            (paymentData["header"] as? [String: Any])?["publicKeyHash"] as? String,
            "AS+1J1234ABCdef="
        )
    }

    /// The edge backfills the IP from the request context and a body value
    /// always wins, so the absent key is the correct one. This is existing
    /// behaviour and the wallet path must not change it.
    func testBrowserInfoStillOmitsTheIPAddress() throws {
        let encoded = try encodedObject(try applePayRequest())
        let browser = try XCTUnwrap(encoded["browser_info"] as? [String: Any])

        XCTAssertFalse(browser.keys.contains("ip_address"))
        XCTAssertEqual(browser["user_agent"] as? String, "PayCrossSDK-iOS/0.2.0")
    }

    func testFieldGroupsAreOmittedWhenEmpty() throws {
        XCTAssertFalse(try encodedObject(try applePayRequest()).keys.contains("field_groups"))

        let withGroups = try applePayRequest(fieldGroups: ["billing": ["postcode": "SW1A 1AA"]])
        XCTAssertTrue(try encodedObject(withGroups).keys.contains("field_groups"))
    }

    /// The card path is untouched. Nothing in this plan may change what a card
    /// payment puts on the wire.
    func testACardRequestIsUnchanged() throws {
        let request = SubmitCardRequest(
            session: "session.jwt.here",
            card: CardData.newCard(
                cardholderName: "A PERSON",
                pan: "4111111111111111",
                expireMonth: "12",
                expireYear: "2030",
                cvv: "123"
            ),
            browserInfo: BrowserInfo(
                userAgent: "ua",
                screenWidth: 1170,
                screenHeight: 2532,
                timezoneOffset: 0,
                language: "en"
            )
        )
        let encoded = try encodedObject(request)

        XCTAssertEqual(encoded["payment_method"] as? String, "card")
        XCTAssertFalse(encoded.keys.contains("wallet_token"))
        XCTAssertTrue(encoded.keys.contains("card"))
    }
}
