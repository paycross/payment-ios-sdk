import XCTest
@testable import DemoHarnessCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DeepLinkTests: XCTestCase {

    private func parse(_ string: String) -> DemoDeepLink? {
        DemoDeepLink.parse(URL(string: string)!)
    }

    func testRunLinkCarriesMerchantScenarioAndSurface() {
        XCTAssertEqual(
            parse("paycross-demo://run?merchant=Acme&scenario=Approve&surface=browser"),
            .run(merchant: "Acme", scenario: "Approve", surface: .browser)
        )
    }

    /// The Kotlin defaults a missing surface to "sdk" rather than rejecting the
    /// link, so a runner can omit it for the common case.
    func testMissingSurfaceDefaultsToTheSDKSheet() {
        XCTAssertEqual(
            parse("paycross-demo://run?merchant=Acme&scenario=Approve"),
            .run(merchant: "Acme", scenario: "Approve", surface: .sdk)
        )
    }

    func testUnknownSurfaceFallsBackRatherThanFailingTheRun() {
        XCTAssertEqual(
            parse("paycross-demo://run?merchant=Acme&scenario=Approve&surface=teleport"),
            .run(merchant: "Acme", scenario: "Approve", surface: .sdk)
        )
    }

    func testSurfaceIsCaseInsensitive() {
        XCTAssertEqual(
            parse("paycross-demo://run?merchant=A&scenario=B&surface=BROWSER"),
            .run(merchant: "A", scenario: "B", surface: .browser)
        )
    }

    func testPercentEncodedNamesDecode() {
        XCTAssertEqual(
            parse("paycross-demo://run?merchant=Acme%20Ltd&scenario=3DS%20challenge"),
            .run(merchant: "Acme Ltd", scenario: "3DS challenge", surface: .sdk)
        )
    }

    func testResultBounce() {
        XCTAssertEqual(parse("paycross-demo://result"), .result)
        XCTAssertEqual(parse("paycross-demo://result?nav=success"), .result)
    }

    func testIncompleteOrForeignLinksAreRejected() {
        XCTAssertNil(parse("paycross-demo://run?merchant=Acme"), "scenario is required")
        XCTAssertNil(parse("paycross-demo://run?scenario=Approve"), "merchant is required")
        XCTAssertNil(parse("paycross-demo://run?merchant=&scenario=x"), "blank is not a name")
        XCTAssertNil(parse("https://example.com/run?merchant=a&scenario=b"))
        XCTAssertNil(parse("paycross-demo://unknown"))
    }
}

final class BodyTemplateTests: XCTestCase {

    func testPlaceholdersAreSubstituted() {
        let body = #"{"merchant_reference":"IOS-{{timestamp}}","key":"{{uuid}}"}"#
        XCTAssertEqual(
            BodyTemplate.substitute(body, timestamp: 1_700_000_000_000, uuid: "abc-123"),
            #"{"merchant_reference":"IOS-1700000000000","key":"abc-123"}"#
        )
    }

    func testBodiesWithoutPlaceholdersAreUnchanged() {
        let body = #"{"amount":1000}"#
        XCTAssertEqual(BodyTemplate.substitute(body, timestamp: 1, uuid: "x"), body)
    }

    func testDeepLinkReturnRewritesBothURLs() throws {
        let body = #"{"amount":1000,"return_url":"https://merchant.example.com/return"}"#
        let out = try BodyTemplate.withDeepLinkReturn(body)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        )
        XCTAssertEqual(json["return_url"] as? String, "paycross-demo://result?nav=return")
        XCTAssertEqual(json["success_url"] as? String, "paycross-demo://result?nav=success")
        XCTAssertEqual(json["amount"] as? Int, 1000, "other fields must survive")
    }

    func testNonObjectBodyIsRejected() {
        XCTAssertThrowsError(try BodyTemplate.withDeepLinkReturn("[1,2,3]"))
        XCTAssertThrowsError(try BodyTemplate.withDeepLinkReturn("not json"))
    }
}

final class SessionOutcomeTests: XCTestCase {

    private func session(status: String, transactions: [[String: Any]] = []) -> [String: Any] {
        ["status": status, "transactions": transactions]
    }

    func testNonTerminalSessionsStayPending() {
        for status in ["pending", "processing", "requires_action"] {
            XCTAssertEqual(SessionOutcome.resolve(session: session(status: status)).phase, .pending)
        }
    }

    func testNonCompletedTerminalStatusesFail() {
        for status in ["failed", "expired", "cancelled"] {
            let result = SessionOutcome.resolve(session: session(status: status))
            XCTAssertEqual(result.phase, .failed)
            XCTAssertEqual(result.detail, "Session \(status)")
        }
    }

    func testCompletedWithASucceededPaymentIsSuccess() {
        let result = SessionOutcome.resolve(session: session(
            status: "completed",
            transactions: [[
                "id": "txn_1", "type": "payment", "status": "succeeded",
                "amount": 2599, "currency": "EUR", "created_at": "2026-01-01T00:00:00Z"
            ]]
        ))
        XCTAssertEqual(result.phase, .success)
        XCTAssertEqual(result.transactionID, "txn_1")
        XCTAssertEqual(result.amount, 2599)
        XCTAssertEqual(result.currency, "EUR")
    }

    func testCompletedWithADeclinedPaymentFails() {
        let result = SessionOutcome.resolve(session: session(
            status: "completed",
            transactions: [["id": "t", "type": "payment", "status": "declined"]]
        ))
        XCTAssertEqual(result.phase, .failed)
    }

    /// A session can complete with no payment transaction at all; reporting that
    /// as success would be the worst possible bug in a test harness.
    func testCompletedWithNoPaymentTransactionFails() {
        let result = SessionOutcome.resolve(session: session(status: "completed"))
        XCTAssertEqual(result.phase, .failed)
        XCTAssertEqual(result.detail, "Completed with no payment transaction")
    }

    /// Refunds and captures carry a parent; the primary payment does not.
    func testTransactionsWithAParentAreIgnored() {
        let result = SessionOutcome.resolve(session: session(
            status: "completed",
            transactions: [
                ["id": "pay", "type": "payment", "status": "succeeded",
                 "created_at": "2026-01-01T00:00:00Z"],
                ["id": "refund", "type": "payment", "status": "refunded",
                 "parent_transaction_id": "pay", "created_at": "2026-01-02T00:00:00Z"]
            ]
        ))
        XCTAssertEqual(result.transactionID, "pay")
        XCTAssertEqual(result.phase, .success)
    }

    func testNonPaymentTypesAreIgnored() {
        let result = SessionOutcome.resolve(session: session(
            status: "completed",
            transactions: [
                ["id": "auth", "type": "verification", "status": "succeeded"],
                ["id": "pay", "type": "payment", "status": "captured",
                 "created_at": "2026-01-01T00:00:00Z"]
            ]
        ))
        XCTAssertEqual(result.transactionID, "pay")
    }

    func testLatestTransactionWins() {
        let result = SessionOutcome.resolve(session: session(
            status: "completed",
            transactions: [
                ["id": "old", "type": "payment", "status": "declined",
                 "created_at": "2026-01-01T00:00:00Z"],
                ["id": "new", "type": "payment", "status": "succeeded",
                 "created_at": "2026-01-01T00:00:00Z",
                 "updated_at": "2026-02-01T00:00:00Z"]
            ]
        ))
        XCTAssertEqual(result.transactionID, "new")
    }

    /// updated_at wins over created_at, and a missing updated_at must not sort
    /// above a present one.
    func testSortKeyPrefersUpdatedAtAndTreatsMissingAsEmpty() {
        XCTAssertEqual(
            SessionOutcome.sortKey(["updated_at": "2026-02-01", "created_at": "2026-01-01"]),
            "2026-02-01"
        )
        XCTAssertEqual(SessionOutcome.sortKey(["created_at": "2026-01-01"]), "2026-01-01")
        XCTAssertEqual(SessionOutcome.sortKey([:]), "")
    }

    func testAllPaidStatusesCount() {
        for status in ["succeeded", "captured", "authorized"] {
            let result = SessionOutcome.resolve(session: session(
                status: "completed",
                transactions: [["id": "t", "type": "payment", "status": status]]
            ))
            XCTAssertEqual(result.phase, .success, "\(status) should count as paid")
        }
    }
}

final class SessionMinterTests: XCTestCase {

    private actor Recorder {
        private(set) var requests: [URLRequest] = []
        func add(_ r: URLRequest) { requests.append(r) }
    }

    private func merchant() -> Merchant {
        Merchant(
            name: "Acme",
            tokenURL: "https://auth.example.com/oauth2/token",
            clientID: "client-id",
            clientSecret: "s3cret",
            paymentAPIURL: "https://api.example.com/payment_sessions",
            paycrossVersion: "2026-01-01"
        )
    }

    func testMintFetchesATokenThenPostsASession() async throws {
        let recorder = Recorder()
        let minter = SessionMinter { request in
            await recorder.add(request)
            let path = request.url?.path ?? ""
            let json = path.contains("token")
                ? #"{"access_token":"tok-1"}"#
                : #"{"id":"sess_1","session_token":"jwt-1","checkout_url":"https://pay/x"}"#
            return (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let minted = try await minter.mint(merchant: merchant(), requestBody: #"{"amount":100}"#)

        XCTAssertEqual(minted.sessionID, "sess_1")
        XCTAssertEqual(minted.sessionToken, "jwt-1")
        XCTAssertEqual(minted.checkoutURL, "https://pay/x")
        // payment_sessions must be normalised to the hyphenated API path.
        XCTAssertEqual(minted.sessionURL, "https://api.example.com/payment-sessions/sess_1")

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Authorization"),
            "Basic \(Data("client-id:s3cret".utf8).base64EncodedString())"
        )
        XCTAssertEqual(
            String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self),
            "grant_type=client_credentials"
        )
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Paycross-Version"), "2026-01-01")
    }

    func testDeepLinkReturnRewritesTheBodyThatIsPosted() async throws {
        let recorder = Recorder()
        let minter = SessionMinter { request in
            await recorder.add(request)
            let json = (request.url?.path ?? "").contains("token")
                ? #"{"access_token":"t"}"#
                : #"{"id":"s","session_token":"j"}"#
            return (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let minted = try await minter.mint(
            merchant: merchant(),
            requestBody: #"{"amount":100}"#,
            deepLinkReturn: true
        )

        XCTAssertTrue(minted.sentBody.contains("paycross-demo://result"))
        let posted = await recorder.requests[1]
        let body = String(decoding: posted.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("paycross-demo://result?nav=return"))
    }

    func testTokenFailureSurfacesTheStatus() async {
        let minter = SessionMinter { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await minter.mint(merchant: merchant(), requestBody: "{}")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? HarnessError, .tokenRequestFailed(401))
        }
    }

    func testSessionFailureCarriesTheBodyForDiagnosis() async {
        let minter = SessionMinter { request in
            let isToken = (request.url?.path ?? "").contains("token")
            return (
                Data((isToken ? #"{"access_token":"t"}"# : #"{"error":"bad amount"}"#).utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: isToken ? 200 : 422,
                    httpVersion: nil, headerFields: nil
                )!
            )
        }
        do {
            _ = try await minter.mint(merchant: merchant(), requestBody: "{}")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(
                error as? HarnessError,
                .sessionRequestFailed(422, #"{"error":"bad amount"}"#)
            )
        }
    }

    /// The generated curl is copied into chat windows and shell histories, so it
    /// must read the secret from the environment rather than embedding it.
    func testGeneratedCurlNeverEmbedsTheClientSecret() {
        let command = CurlBuilder.mintCommand(merchant: merchant(), body: #"{"amount":100}"#)
        XCTAssertFalse(command.contains("s3cret"))
        XCTAssertTrue(command.contains("PAYCROSS_CLIENT_SECRET"))
        XCTAssertTrue(command.contains("https://api.example.com/payment-sessions"))
    }
}

final class DemoDataTests: XCTestCase {

    func testRunHistoryIsBoundedAndNewestFirst() {
        var data = DemoData()
        for index in 0..<(DemoData.maxRuns + 10) {
            data.record(RunRecord(id: "run-\(index)", scenarioName: "s\(index)"))
        }
        XCTAssertEqual(data.runs.count, DemoData.maxRuns)
        XCTAssertEqual(data.runs.first?.id, "run-\(DemoData.maxRuns + 9)")
    }

    func testSurfacesOtherThanTheSDKSheetNeedPolling() {
        XCTAssertFalse(CheckoutSurface.sdk.requiresPolling)
        for surface in [CheckoutSurface.browser, .link, .qr] {
            XCTAssertTrue(surface.requiresPolling, "\(surface) has no SDK callback")
        }
    }

    func testDemoDataRoundTripsThroughCodable() throws {
        var data = DemoData(
            merchants: [Merchant(name: "Acme")],
            scenarios: [Scenario(merchantID: "m", name: "Approve", requestBody: "{}")]
        )
        data.record(RunRecord(scenarioName: "Approve", surface: .qr))

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(DemoData.self, from: encoded)

        XCTAssertEqual(decoded.merchants.first?.name, "Acme")
        XCTAssertEqual(decoded.runs.first?.surface, .qr)
    }

    func testSessionsURLNormalisesTheLegacyUnderscorePath() {
        let merchant = Merchant(paymentAPIURL: "https://api.example.com/payment_sessions")
        XCTAssertEqual(merchant.sessionsURL, "https://api.example.com/payment-sessions")
    }

    func testPrefillIsOnlyUsableWithAPAN() {
        XCTAssertFalse(CardPrefill().isUsable)
        XCTAssertFalse(CardPrefill(pan: "   ").isUsable)
        XCTAssertTrue(CardPrefill(pan: "4111111111111111").isUsable)
    }
}
