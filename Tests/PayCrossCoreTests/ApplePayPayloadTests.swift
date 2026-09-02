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
          "applicationData": "OGZlZDA5ODc2NTQzMjE=",
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
        XCTAssertEqual(paymentData["data"] as? String, "l6ptDgUVfd9...")
        XCTAssertEqual(paymentData["signature"] as? String, "MIAGCSqGSIb3...")
        XCTAssertEqual(header["applicationData"] as? String, "OGZlZDA5ODc2NTQzMjE=")
        XCTAssertEqual(header["ephemeralPublicKey"] as? String, "MFkwEwYHKoZIzj0CAQ...")
        XCTAssertEqual(header["publicKeyHash"] as? String, "AS+1J1234ABCdef=")
        XCTAssertEqual(header["transactionId"] as? String, "31323334353637")

        let method = try XCTUnwrap(encoded["paymentMethod"] as? [String: Any])
        XCTAssertEqual(method["displayName"] as? String, "Visa 1234")
        XCTAssertEqual(method["network"] as? String, "Visa")
        XCTAssertEqual(method["type"] as? String, "debit")
        XCTAssertEqual(encoded["transactionIdentifier"] as? String, "31323334353637")

        // The nested key sets as well as the values. A value assertion catches
        // a dropped key it names; these catch one it does not, so a field added
        // to the fixture cannot sit unasserted the way `data` and
        // `ephemeralPublicKey` once did.
        XCTAssertEqual(Set(paymentData.keys), ["version", "data", "signature", "header"])
        XCTAssertEqual(
            Set(header.keys),
            ["applicationData", "ephemeralPublicKey", "publicKeyHash", "transactionId"]
        )
        XCTAssertEqual(Set(method.keys), ["displayName", "network", "type"])
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

    /// The `Int64` branch, pinned. The test above does not reach it: Foundation
    /// encodes a whole `Double` without an exponent, so routing every number
    /// through `Double` still satisfies it. Above 2^53 a `Double` runs out of
    /// mantissa and the value silently changes, which is the failure a long
    /// numeric identifier in Apple's token would actually suffer.
    func testAnIntegerTooLargeForADoubleKeepsEveryDigit() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n": 9007199254740993}"#.utf8))
        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(value), encoding: .utf8))

        XCTAssertTrue(encoded.contains("9007199254740993"), encoded)
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

        let empties = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"o": {}, "a": []}"#.utf8))
        let encodedEmpties = try encodedObject(empties)

        XCTAssertEqual((encodedEmpties["o"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual((encodedEmpties["a"] as? [Any])?.isEmpty, true)
    }

    func testAnEscapedStringSurvives() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"s": "a\"b\\c\nd"}"#.utf8))
        let encoded = try encodedObject(value)

        XCTAssertEqual(encoded["s"] as? String, "a\"b\\c\nd")

        // `paymentMethod.displayName` carries the card's own label and is the
        // field most likely to arrive non-ASCII.
        let unicode = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"s": "café ¥ 😀"}"#.utf8))

        XCTAssertEqual(try encodedObject(unicode)["s"] as? String, "café ¥ 😀")
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

    func testAWhitespaceOnlyIdentifierCannotBuildAToken() throws {
        XCTAssertNil(WalletToken.applePay(data: try decodedToken(), merchantIdentifier: "   "))
    }

    /// A merchant reads this identifier out of a plist, an environment
    /// variable or a copied console field, and every one of those can deliver
    /// it padded. The gate trims before offering the button, so a padded
    /// identifier gets all the way to Face ID; the edge then compares the body
    /// against the signed session claim byte for byte and answers a 400. The
    /// builder has to agree with the gate or the two guards describe different
    /// identifiers.
    func testAPaddedIdentifierReachesTheEdgeTrimmed() throws {
        let padded = try applePayRequest(merchantIdentifier: "  merchant.pay-cross.com\n")
        let wallet = try XCTUnwrap(try encodedObject(padded)["wallet_token"] as? [String: Any])

        XCTAssertEqual(wallet["merchant_identifier"] as? String, "merchant.pay-cross.com")
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

    // MARK: - The request spec

    private func claims(minorUnits: Int64 = 1234, currency: String = "GBP") -> SessionClaims {
        SessionClaims(
            sessionID: "sess_1",
            merchantID: "merchant-uuid",
            customerID: "customer-uuid",
            brandingID: nil,
            amount: Amount(minorUnits: minorUnits, currencyCode: currency),
            expiresAt: nil
        )
    }

    private func spec(
        merchantCountry: String? = "GB",
        hasData: Bool = true,
        minorUnits: Int64 = 1234,
        currency: String = "GBP"
    ) -> ApplePayRequestSpec {
        ApplePayRequestSpec.make(
            claims: claims(minorUnits: minorUnits, currency: currency),
            data: hasData ? SessionData(merchantCountry: merchantCountry) : nil,
            merchantIdentifier: "merchant.pay-cross.com"
        )
    }

    func testTheCountryComesFromTheSession() {
        XCTAssertEqual(spec().countryCode, "GB")
    }

    /// Apple refuses a request with no country, and the session is allowed not
    /// to name one. US is the fallback the design fixed; it is a default, not
    /// a guess about the shopper.
    func testTheCountryFallsBackWhenTheSessionNamesNone() {
        XCTAssertEqual(spec(merchantCountry: nil).countryCode, "US")
    }

    func testTheCountryFallsBackWhenThereIsNoSessionDataAtAll() {
        XCTAssertEqual(spec(hasData: false).countryCode, "US")
    }

    /// PassKit wants ISO 3166-1 alpha-2 in its conventional case, and the
    /// session is not guaranteed to send it that way. Every other consumer in
    /// this repo already defends against the lowercase spelling.
    func testALowercaseCountryIsUppercased() {
        XCTAssertEqual(spec(merchantCountry: "gb").countryCode, "GB")
    }

    func testTheAmountAndCurrencyComeFromTheClaims() {
        let built = spec(minorUnits: 100, currency: "EUR")

        XCTAssertEqual(built.currencyCode, "EUR")
        XCTAssertEqual(built.amount.minorUnits, 100)
    }

    /// ISO 4217, same argument as the country. `Amounts` already uppercases at
    /// three call sites, so within this one struct `amountMajorUnits` survived
    /// a lowercase currency while `currencyCode` handed it to PassKit as it
    /// arrived. A sheet that fails to present fails at the moment of payment.
    func testALowercaseCurrencyIsUppercased() {
        XCTAssertEqual(spec(currency: "gbp").currencyCode, "GBP")
    }

    func testTheMajorUnitAmountIsExactForATwoDecimalCurrency() {
        XCTAssertEqual(spec(minorUnits: 1234, currency: "GBP").amountMajorUnits, Decimal(string: "12.34"))
    }

    /// A zero-decimal currency divides by one, not by a hundred. Sending
    /// Apple 12.34 for ¥1234 would quote the shopper the wrong price on the
    /// sheet, which is the one number they read before authorising.
    func testTheMajorUnitAmountIsExactForAZeroDecimalCurrency() {
        XCTAssertEqual(spec(minorUnits: 1234, currency: "JPY").amountMajorUnits, Decimal(1234))
    }

    func testTheNetworksAndCapabilitiesAreTheAgreedLists() {
        let built = spec()

        XCTAssertEqual(built.supportedNetworks, [.visa, .mastercard, .amex, .discover, .jcb])
        XCTAssertEqual(built.capabilities, [.threeDSecure, .credit, .debit])
    }

    func testTheMerchantIdentifierAndLabelAreCarried() {
        let built = spec()

        XCTAssertEqual(built.merchantIdentifier, "merchant.pay-cross.com")
        XCTAssertEqual(built.summaryItemLabel, "Total")
    }

    // MARK: - Through a fake authorizer

    /// The whole Core-side path in one test: a spec goes to an authorizer, an
    /// authorised token comes back, and it becomes a submit body. Nothing in
    /// this file mocks the payload builder, so this is the assertion that
    /// would fail if the pieces stopped fitting together.
    func testAnAuthorizedTokenBecomesASubmitBody() async throws {
        // An actor rather than a class with `@unchecked Sendable`: the
        // protocol is Sendable and the fake holds mutable state, and an
        // actor satisfies both without an escape hatch that would also
        // silence a real race in the shipping adapter.
        actor FakeAuthorizer: WalletAuthorizing {
            private(set) var received: ApplePayRequestSpec?
            private let token: JSONValue
            init(token: JSONValue) { self.token = token }
            func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome {
                received = spec
                return .authorized(token)
            }
        }

        let authorizer = FakeAuthorizer(token: try decodedToken())
        let outcome = await authorizer.authorize(spec())

        let received = await authorizer.received
        XCTAssertEqual(received?.merchantIdentifier, "merchant.pay-cross.com")
        guard case .authorized(let token) = outcome else {
            return XCTFail("expected an authorized outcome, got \(outcome)")
        }

        let request = SubmitCardRequest(
            session: "session.jwt.here",
            walletToken: try XCTUnwrap(
                WalletToken.applePay(data: token, merchantIdentifier: "merchant.pay-cross.com")
            ),
            browserInfo: BrowserInfo(
                userAgent: "ua",
                screenWidth: 1170,
                screenHeight: 2532,
                timezoneOffset: 0,
                language: "en"
            )
        )
        let wallet = try XCTUnwrap(try encodedObject(request)["wallet_token"] as? [String: Any])

        XCTAssertEqual(wallet["merchant_identifier"] as? String, "merchant.pay-cross.com")
    }
}
