import XCTest
@testable import PayCrossCore

final class SessionTokenTests: XCTestCase {

    /// Builds a JWT with the given payload. The signature is nonsense on purpose —
    /// the SDK does not verify it, the server does.
    private func makeToken(_ payload: [String: Any]) throws -> String {
        let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8)
        let body = try JSONSerialization.data(withJSONObject: payload)
        return [base64URL(header), base64URL(body), "not-a-real-signature"].joined(separator: ".")
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testDecodesAFullPayload() throws {
        let token = try makeToken([
            "sub": "sess_abc",
            "merchant": "merch_1",
            "customer": "cust_1",
            "branding": "brand_1",
            "amount": 2599,
            "currency": "EUR",
            "exp": 1_800_000_000
        ])

        let claims = try SessionTokenDecoder.decode(token)
        XCTAssertEqual(claims.sessionID, "sess_abc")
        XCTAssertEqual(claims.merchantID, "merch_1")
        XCTAssertEqual(claims.customerID, "cust_1")
        XCTAssertEqual(claims.brandingID, "brand_1")
        XCTAssertEqual(claims.amount, Amount(minorUnits: 2599, currencyCode: "EUR"))
        XCTAssertEqual(claims.expiresAt, 1_800_000_000)
    }

    /// Android defaults merchant/customer to "" and maps empty branding to null.
    func testOptionalClaimsMatchAndroidDefaults() throws {
        let token = try makeToken([
            "sub": "sess_abc", "amount": 100, "currency": "USD", "branding": ""
        ])
        let claims = try SessionTokenDecoder.decode(token)
        XCTAssertEqual(claims.merchantID, "")
        XCTAssertEqual(claims.customerID, "")
        XCTAssertNil(claims.brandingID)
        XCTAssertNil(claims.expiresAt)
    }

    func testRequiredClaimsAreEnforced() throws {
        let noAmount = try makeToken(["sub": "s", "currency": "EUR"])
        XCTAssertThrowsError(try SessionTokenDecoder.decode(noAmount)) {
            XCTAssertEqual($0 as? SessionTokenError, .missingField("amount"))
        }

        let noSub = try makeToken(["amount": 1, "currency": "EUR"])
        XCTAssertThrowsError(try SessionTokenDecoder.decode(noSub)) {
            XCTAssertEqual($0 as? SessionTokenError, .missingField("sub"))
        }
    }

    func testNullClaimsAreTreatedAsAbsent() throws {
        let token = try makeToken([
            "sub": "s", "amount": 1, "currency": "EUR", "exp": NSNull(), "branding": NSNull()
        ])
        let claims = try SessionTokenDecoder.decode(token)
        XCTAssertNil(claims.expiresAt)
        XCTAssertNil(claims.brandingID)
    }

    func testMalformedTokensThrow() {
        XCTAssertThrowsError(try SessionTokenDecoder.decode("")) {
            XCTAssertEqual($0 as? SessionTokenError, .empty)
        }
        XCTAssertThrowsError(try SessionTokenDecoder.decode("only.two"))
        XCTAssertThrowsError(try SessionTokenDecoder.decode("a.!!!not-base64!!!.c"))
    }

    /// Real JWTs are base64url without padding; a decoder that forgets to repad
    /// fails on payload lengths that are not a multiple of 4.
    func testUnpaddedBase64URLPayloadsDecode() throws {
        for filler in ["a", "ab", "abc", "abcd"] {
            let token = try makeToken([
                "sub": "s\(filler)", "amount": 1, "currency": "EUR"
            ])
            XCTAssertNoThrow(try SessionTokenDecoder.decode(token), "failed for filler \(filler)")
        }
    }

    func testExpiryComparison() throws {
        let token = try makeToken(["sub": "s", "amount": 1, "currency": "EUR", "exp": 1000])
        let claims = try SessionTokenDecoder.decode(token)
        XCTAssertTrue(claims.isExpired(now: Date(timeIntervalSince1970: 1000)))
        XCTAssertTrue(claims.isExpired(now: Date(timeIntervalSince1970: 2000)))
        XCTAssertFalse(claims.isExpired(now: Date(timeIntervalSince1970: 999)))
    }
}

final class WireModelTests: XCTestCase {

    func testStatusResponseDecodesSnakeCaseKeys() throws {
        let json = Data("""
        {
          "transaction_id": "txn_1",
          "status": "threeds_challenge",
          "amount": 1500,
          "currency": "EUR",
          "action": { "url": "https://acs/x", "method": "POST", "data": { "a": "1" } },
          "recovery": null
        }
        """.utf8)

        let status = try JSONDecoder().decode(StatusResponse.self, from: json)
        XCTAssertEqual(status.transactionID, "txn_1")
        XCTAssertEqual(status.amount, 1500)
        XCTAssertEqual(status.action?.url, "https://acs/x")
        XCTAssertTrue(status.action?.isPost == true)
        XCTAssertNil(status.recovery)
    }

    func testSubmitCardResponseDecodesRetryAfter() throws {
        let json = Data(#"{"success":false,"error":"processing","retry_after":3}"#.utf8)
        let response = try JSONDecoder().decode(SubmitCardResponse.self, from: json)
        XCTAssertEqual(response.retryAfter, 3)
        XCTAssertEqual(response.success, false)
        XCTAssertNil(response.transactionID)
    }

    func testMinimalStatusResponseDecodes() throws {
        let json = Data(#"{"transaction_id":"t","status":"success"}"#.utf8)
        let status = try JSONDecoder().decode(StatusResponse.self, from: json)
        XCTAssertNil(status.amount)
        XCTAssertNil(status.action)
    }
}
