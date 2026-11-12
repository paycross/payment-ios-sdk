import XCTest
@testable import PayCrossCore

final class ApplePayPayloadTests: XCTestCase {
    /// A PassKit token as the web posts it, with the envelope at the top level.
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

    func testAnIntegerIsNotTurnedIntoAFloat() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n": 1234567890123}"#.utf8))
        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(value), encoding: .utf8))

        XCTAssertTrue(encoded.contains("1234567890123"), encoded)
        XCTAssertFalse(encoded.contains("e+"), encoded)
    }

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

    func testNoCardObjectIsSent() throws {
        let encoded = try encodedObject(try applePayRequest())

        XCTAssertFalse(encoded.keys.contains("card"))
    }

    func testTheWalletTokenTypeMatchesThePaymentMethod() throws {
        let encoded = try encodedObject(try applePayRequest())
        let wallet = try XCTUnwrap(encoded["wallet_token"] as? [String: Any])

        // The edge refuses a wallet body whose token type differs from payment_method.
        XCTAssertEqual(wallet["type"] as? String, "apple_pay")
        XCTAssertEqual(wallet["type"] as? String, encoded["payment_method"] as? String)
    }

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

    func testTheCountryFallsBackWhenTheSessionNamesNone() {
        XCTAssertEqual(spec(merchantCountry: nil).countryCode, "US")
    }

    func testTheCountryFallsBackWhenThereIsNoSessionDataAtAll() {
        XCTAssertEqual(spec(hasData: false).countryCode, "US")
    }

    func testALowercaseCountryIsUppercased() {
        XCTAssertEqual(spec(merchantCountry: "gb").countryCode, "GB")
    }

    func testTheAmountAndCurrencyComeFromTheClaims() {
        let built = spec(minorUnits: 100, currency: "EUR")

        XCTAssertEqual(built.currencyCode, "EUR")
        XCTAssertEqual(built.amount.minorUnits, 100)
    }

    func testALowercaseCurrencyIsUppercased() {
        XCTAssertEqual(spec(currency: "gbp").currencyCode, "GBP")
    }

    func testTheMajorUnitAmountIsExactForATwoDecimalCurrency() {
        XCTAssertEqual(spec(minorUnits: 1234, currency: "GBP").amountMajorUnits, Decimal(string: "12.34"))
    }

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

    func testOutcomesCompareByCaseAndByPayload() throws {
        let token = try decodedToken()

        XCTAssertEqual(WalletAuthorizationOutcome.cancelled, .cancelled)
        XCTAssertEqual(WalletAuthorizationOutcome.authorized(token), .authorized(token))
        XCTAssertNotEqual(WalletAuthorizationOutcome.cancelled, .failed("declined"))
        XCTAssertNotEqual(WalletAuthorizationOutcome.failed("a"), .failed("b"))
    }

    func testAnAuthorizedTokenBecomesASubmitBody() async throws {
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

    func testTheSpecOffersEveryNetworkTheDeviceCheckAsksAbout() {
        XCTAssertEqual(
            Set(spec().supportedNetworks), Set(ApplePayNetwork.allCases),
            "the eligibility check and the payment request must ask about the same schemes"
        )
    }
}
