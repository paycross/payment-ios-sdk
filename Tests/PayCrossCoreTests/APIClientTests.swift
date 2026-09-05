import XCTest
@testable import PayCrossCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records what was sent and replays canned responses. No server, no URLProtocol.
///
/// An actor rather than a lock-guarded class: `send` is async, and Swift 6 refuses
/// `NSLock` across a suspension point.
private actor StubTransport: HTTPTransport {
    struct Reply {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
    }

    private var replies: [Reply]
    private(set) var sent: [URLRequest] = []

    init(replies: [Reply]) {
        self.replies = replies
    }

    init(status: Int = 200, json: String = "{}") {
        self.replies = [Reply(status: status, body: Data(json.utf8))]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        let reply = replies.isEmpty ? Reply() : replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (reply.body, response)
    }
}

final class APIClientTests: XCTestCase {

    private let baseURL = URL(string: "https://checkout.test-pay-cross.com/api")!

    private func makeClient(_ transport: HTTPTransport) -> PayCrossAPIClient {
        PayCrossAPIClient(baseURL: baseURL, transport: transport, userAgent: "PayCrossSDK-iOS/test")
    }

    func testStatusRequestShape() async throws {
        let transport = StubTransport(json: #"{"transaction_id":"t1","status":"success"}"#)
        let response = try await makeClient(transport).status(transactionID: "t1")

        XCTAssertEqual(response.transactionID, "t1")
        let request = await transport.sent[0]
        XCTAssertEqual(request.url?.absoluteString, "https://checkout.test-pay-cross.com/api/status/t1")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PayCrossSDK-iOS/test")
    }

    /// A cached status poll can freeze the caller on a stale value: a live test
    /// drive saw the second poll after submit come back `cache_hit=true` from
    /// URLSession's URLCache. Every request from this client is a payments API
    /// call, none of which is cacheable, so none may be cache-served. All three
    /// go through `makeRequest` today, but this asserts each call site
    /// directly rather than trusting that they keep sharing it.
    func testRequestsBypassURLCache() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(#"{"transaction_id":"t1","status":"success"}"#.utf8)),
            .init(body: Data(#"{"session_id":"s1","status":"open"}"#.utf8)),
            .init(body: Data(#"{"success":true,"transaction_id":"t1"}"#.utf8)),
        ])
        let client = makeClient(transport)

        _ = try await client.status(transactionID: "t1")
        _ = try await client.session(id: "s1", sessionToken: "jwt-here")
        _ = try await client.submitCard(
            SubmitCardRequest(
                session: "jwt",
                card: .newCard(
                    cardholderName: "A PERSON",
                    pan: "4111111111111111",
                    expireMonth: "12",
                    expireYear: "2030",
                    cvv: "123"
                ),
                browserInfo: sampleBrowserInfo
            ),
            idempotencyKey: "key-1"
        )

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 3)
        for request in sent {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        }
    }

    func testSessionRequestCarriesBearerToken() async throws {
        let transport = StubTransport(json: #"{"session_id":"s1","status":"open"}"#)
        _ = try await makeClient(transport).session(id: "s1", sessionToken: "jwt-here")

        let request = await transport.sent[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-here")
    }

    func testSubmitCardSendsIdempotencyKeyAndJSONBody() async throws {
        let transport = StubTransport(json: #"{"success":true,"transaction_id":"t1"}"#)
        let body = SubmitCardRequest(
            session: "jwt",
            card: .newCard(
                cardholderName: "A PERSON",
                pan: "4111111111111111",
                expireMonth: "12",
                expireYear: "2030",
                cvv: "123"
            ),
            browserInfo: sampleBrowserInfo
        )

        let response = try await makeClient(transport).submitCard(body, idempotencyKey: "key-1")
        XCTAssertEqual(response.transactionID, "t1")

        let request = await transport.sent[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "key-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // The wire body must use the snake_case names the backend documents.
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(json["payment_method"] as? String, "card")
        let card = try XCTUnwrap(json["card"] as? [String: Any])
        XCTAssertEqual(card["pan"] as? String, "4111111111111111")
        XCTAssertEqual(card["expire_month"] as? String, "12")
        XCTAssertNotNil(json["browser_info"])
    }

    func testUnauthorizedBecomesSessionExpired() async {
        let transport = StubTransport(status: 401)
        do {
            _ = try await makeClient(transport).status(transactionID: "t1")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? PayCrossError, .sessionExpired)
        }
    }

    func testNon2xxSurfacesStatusAndBody() async {
        let transport = StubTransport(status: 400, json: #"{"error":"bad"}"#)
        do {
            _ = try await makeClient(transport).status(transactionID: "t1")
            XCTFail("expected a throw")
        } catch let error as PayCrossError {
            guard case .http(let status, let body) = error else { return XCTFail("wrong case") }
            XCTAssertEqual(status, 400)
            XCTAssertEqual(body, #"{"error":"bad"}"#)
        } catch {
            XCTFail("wrong error type")
        }
    }

    /// Only a server-side rejection is safe to retry. A dropped connection is not:
    /// the request may already have been received.
    func testOnlyConflictsAreRetryableRejections() {
        XCTAssertTrue(PayCrossError.http(status: 409, body: nil).isRetryableRejection)
        XCTAssertFalse(PayCrossError.http(status: 400, body: nil).isRetryableRejection)
        XCTAssertFalse(PayCrossError.transport("timed out").isRetryableRejection)
        XCTAssertFalse(PayCrossError.sessionExpired.isRetryableRejection)
    }

    func testMalformedBodyBecomesDecodingError() async {
        let transport = StubTransport(json: "not json at all")
        do {
            _ = try await makeClient(transport).status(transactionID: "t1")
            XCTFail("expected a throw")
        } catch let error as PayCrossError {
            guard case .decoding = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type")
        }
    }

    /// A hostile identifier must not be able to climb out of the API path.
    func testPathSegmentsArePercentEncoded() async throws {
        let transport = StubTransport(json: #"{"transaction_id":"t","status":"success"}"#)
        _ = try? await makeClient(transport).status(transactionID: "../session/secret")

        let sent = await transport.sent
        let path = try XCTUnwrap(sent.first?.url?.absoluteString)
        XCTAssertFalse(path.contains("/api/session/secret"), "path traversal: \(path)")
    }

    // MARK: - Removing a saved card

    func testDeleteSavedCardRequestShape() async throws {
        let transport = StubTransport(status: 204, json: "")
        try await makeClient(transport).deleteSavedCard(uuid: "card_1", sessionToken: "jwt-here")

        let request = await transport.sent[0]
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://checkout.test-pay-cross.com/api/saved-cards/card_1"
        )
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-here")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    /// The endpoint is idempotent and answers 204 whether or not the card was
    /// still active, so a second removal is a success and not an error.
    func testDeleteSavedCardTreats204AsSuccess() async throws {
        let transport = StubTransport(replies: [
            .init(status: 204, body: Data()),
            .init(status: 204, body: Data())
        ])
        let client = makeClient(transport)

        try await client.deleteSavedCard(uuid: "card_1", sessionToken: "jwt")
        try await client.deleteSavedCard(uuid: "card_1", sessionToken: "jwt")

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 2)
    }

    /// 404 is the ownership check failing — the card is not this session's
    /// customer's — and is distinct from a transient failure because there is
    /// nothing to retry.
    func testDeleteSavedCardTreats404AsNotFound() async {
        let transport = StubTransport(status: 404, json: #"{"error":"not found"}"#)
        do {
            try await makeClient(transport).deleteSavedCard(uuid: "card_1", sessionToken: "jwt")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? PayCrossError, .notFound)
        }
    }

    func testDeleteSavedCardTreats401AsSessionExpired() async {
        let transport = StubTransport(status: 401)
        do {
            try await makeClient(transport).deleteSavedCard(uuid: "card_1", sessionToken: "jwt")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? PayCrossError, .sessionExpired)
        }
    }

    func testDeleteSavedCardSurfacesOtherFailures() async {
        let transport = StubTransport(status: 500, json: #"{"error":"boom"}"#)
        do {
            try await makeClient(transport).deleteSavedCard(uuid: "card_1", sessionToken: "jwt")
            XCTFail("expected a throw")
        } catch let error as PayCrossError {
            guard case .http(let status, _) = error else { return XCTFail("wrong case: \(error)") }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("wrong error type")
        }
    }

    /// A 404 on the status poll must stay an `.http` failure: the row is still
    /// being written while the poll runs, and reading that as "gone" would end
    /// a live payment. Only the no-content path reads 404 as a missing resource.
    func testA404OnAPollIsStillAnHTTPFailure() async {
        let transport = StubTransport(status: 404, json: #"{"error":"not found"}"#)
        do {
            _ = try await makeClient(transport).status(transactionID: "t1")
            XCTFail("expected a throw")
        } catch let error as PayCrossError {
            guard case .http(let status, _) = error else { return XCTFail("wrong case: \(error)") }
            XCTAssertEqual(status, 404)
        } catch {
            XCTFail("wrong error type")
        }
    }

    // MARK: - browser_info

    /// 3DS expects the JavaScript getTimezoneOffset() convention: minutes WEST of
    /// UTC. A device at UTC+2 reports -120. The sign is easy to invert and a stale
    /// design doc in this repo's history had it backwards.
    func testTimezoneOffsetIsMinutesWestOfUTC() {
        let berlinSummer = TimeZone(identifier: "Europe/Berlin")!
        let july = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03, CEST (UTC+2)
        XCTAssertEqual(
            BrowserInfo.timezoneOffsetMinutes(timeZone: berlinSummer, at: july),
            -120
        )

        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(
            BrowserInfo.timezoneOffsetMinutes(timeZone: newYork, at: july),
            240 // UTC-4 in summer
        )

        XCTAssertEqual(
            BrowserInfo.timezoneOffsetMinutes(timeZone: TimeZone(identifier: "UTC")!, at: july),
            0
        )
    }

    func testBrowserInfoEncodesSnakeCase() throws {
        let data = try JSONEncoder().encode(sampleBrowserInfo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Non-EMPTY, not merely non-nil: the backend trims and rejects blanks,
        // and "" is present-but-invalid. Asserting presence is what allowed an
        // SDK whose ip_address was always "" to pass this test.
        //
        // ip_address is not in this list: the server derives it when the client
        // omits it, so it is no longer a client-required field. See the
        // ip_address-specific tests below.
        for key in ["user_agent", "language", "accept_header"] {
            let value = json[key] as? String
            XCTAssertNotNil(value, "\(key) missing")
            XCTAssertFalse(
                (value ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                "\(key) is blank; the backend rejects it"
            )
        }
        XCTAssertNotNil(json["screen_width"])
        XCTAssertNotNil(json["timezone_offset"])
        XCTAssertEqual(json["java_enabled"] as? Bool, false)
        XCTAssertEqual(json["javascript_enabled"] as? Bool, true)
        XCTAssertEqual(json["color_depth"] as? Int, 24)
    }

    /// The server derives `ip_address` from the request (Cloudflare header ->
    /// source IP) when the client omits it. Sending the key as `null` would
    /// still trip the backend's blank check, so a nil `ipAddress` must produce
    /// no key at all -- not `"ip_address": null`.
    func testBrowserInfoOmitsIPAddressKeyWhenNil() throws {
        let info = BrowserInfo(
            userAgent: "test-agent", screenWidth: 390, screenHeight: 844,
            timezoneOffset: -120, language: "en-GB"
        )
        XCTAssertNil(info.ipAddress)

        let data = try JSONEncoder().encode(info)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse(json.keys.contains("ip_address"), "ip_address must be absent, not null")
    }

    /// A client-supplied value still wins over the server's derivation.
    func testBrowserInfoEncodesIPAddressWhenPresent() throws {
        let info = BrowserInfo(
            userAgent: "test-agent", ipAddress: "192.0.2.1", screenWidth: 390,
            screenHeight: 844, timezoneOffset: -120, language: "en-GB"
        )

        let data = try JSONEncoder().encode(info)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["ip_address"] as? String, "192.0.2.1")
    }

    // MARK: - Redaction

    /// The submit body carries a PAN and a CVV and is reachable from a merchant's
    /// test target, so interpolating it must not leak either.
    func testCardDataDescriptionRedactsPANAndCVV() {
        let card = CardData.newCard(
            cardholderName: "A PERSON",
            pan: "4111111111111111",
            expireMonth: "12",
            expireYear: "2030",
            cvv: "987"
        )
        let rendered = "\(card)"
        XCTAssertFalse(rendered.contains("4111111111111111"))
        XCTAssertFalse(rendered.contains("987"))
        XCTAssertTrue(rendered.contains("1111"), "last four is fine and useful")

        let request = SubmitCardRequest(session: "jwt", card: card, browserInfo: sampleBrowserInfo)
        XCTAssertFalse("\(request)".contains("4111111111111111"))
    }

    private var sampleBrowserInfo: BrowserInfo {
        BrowserInfo(
            userAgent: "test-agent",
            ipAddress: "192.0.2.1",
            screenWidth: 390,
            screenHeight: 844,
            timezoneOffset: -120,
            language: "en-GB"
        )
    }
}
