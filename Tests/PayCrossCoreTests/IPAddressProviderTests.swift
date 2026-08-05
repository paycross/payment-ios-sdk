import XCTest
@testable import PayCrossCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor CountingTransport: HTTPTransport {
    private let status: Int
    private let json: String
    private let shouldThrow: Bool
    private(set) var calls = 0

    init(status: Int = 200, json: String = #"{"ip":"203.0.113.7"}"#, shouldThrow: Bool = false) {
        self.status = status
        self.json = json
        self.shouldThrow = shouldThrow
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if shouldThrow { throw PayCrossError.transport("offline") }
        return (
            Data(json.utf8),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}

/// The backend rejects a blank ip_address outright (validateBrowserInfo in
/// payment-submit-card), so this is the difference between an SDK that can
/// submit and one that cannot.
final class IPAddressProviderTests: XCTestCase {

    func testResolvesThePublicIP() async {
        let provider = IPAddressProvider(transport: CountingTransport())
        let ip = await provider.current()
        XCTAssertEqual(ip, "203.0.113.7")
    }

    func testResultIsCachedSoSubmitDoesNotPayTwice() async {
        let transport = CountingTransport()
        let provider = IPAddressProvider(transport: transport)

        _ = await provider.current()
        _ = await provider.current()
        _ = await provider.current()

        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    /// A failing lookup must never block a payment; loopback is submittable.
    func testNetworkFailureFallsBackToLoopback() async {
        let provider = IPAddressProvider(transport: CountingTransport(shouldThrow: true))
        let ip = await provider.current()
        XCTAssertEqual(ip, IPAddressProvider.fallback)
        XCTAssertFalse(ip.isEmpty, "a blank ip_address is rejected by the backend")
    }

    func testNon2xxFallsBack() async {
        let provider = IPAddressProvider(transport: CountingTransport(status: 503))
        let ip = await provider.current()
        XCTAssertEqual(ip, IPAddressProvider.fallback)
    }

    func testMalformedOrBlankResponsesFallBack() async {
        for json in ["not json", #"{}"#, #"{"ip":""}"#, #"{"ip":"   "}"#, #"{"ip":42}"#] {
            let provider = IPAddressProvider(transport: CountingTransport(json: json))
            let ip = await provider.current()
            XCTAssertEqual(ip, IPAddressProvider.fallback, "failed for \(json)")
        }
    }

    func testWarmPopulatesTheCache() async {
        let transport = CountingTransport()
        let provider = IPAddressProvider(transport: transport)

        await provider.warm()
        _ = await provider.current()

        let calls = await transport.calls
        XCTAssertEqual(calls, 1, "warming should mean submit pays nothing")
    }
}

/// Guards the exact hole that let a non-submittable SDK ship green: the previous
/// test asserted these keys were *present*, and an empty string satisfies that.
final class BrowserInfoSubmittabilityTests: XCTestCase {

    private func info(
        userAgent: String = "Mozilla/5.0",
        ipAddress: String = "203.0.113.7",
        language: String = "en-GB",
        acceptHeader: String = BrowserInfo.defaultAcceptHeader
    ) -> BrowserInfo {
        BrowserInfo(
            userAgent: userAgent, ipAddress: ipAddress, screenWidth: 1170,
            screenHeight: 2532, timezoneOffset: 0, language: language,
            acceptHeader: acceptHeader
        )
    }

    func testCompleteInfoIsSubmittable() {
        XCTAssertTrue(info().isSubmittable)
        XCTAssertTrue(info().missingRequiredFields.isEmpty)
    }

    /// One case per field the Go validator checks.
    func testEachBackendRequiredFieldIsEnforced() {
        XCTAssertEqual(info(userAgent: "").missingRequiredFields, ["user_agent"])
        XCTAssertEqual(info(ipAddress: "").missingRequiredFields, ["ip_address"])
        XCTAssertEqual(info(language: "").missingRequiredFields, ["language"])
        XCTAssertEqual(info(acceptHeader: "").missingRequiredFields, ["accept_header"])
    }

    /// The backend trims before checking, so whitespace is not a value.
    func testWhitespaceDoesNotCountAsPresent() {
        XCTAssertFalse(info(ipAddress: "   ").isSubmittable)
        XCTAssertFalse(info(userAgent: "\n").isSubmittable)
    }

    func testAllMissingFieldsAreReportedTogether() {
        XCTAssertEqual(
            info(userAgent: "", ipAddress: "", language: "").missingRequiredFields,
            ["user_agent", "ip_address", "language"]
        )
    }

    /// The value that would have shipped: structurally valid, rejected on arrival.
    func testTheShippedDefectIsCaught() {
        XCTAssertFalse(
            info(ipAddress: "").isSubmittable,
            "an empty ip_address encodes fine and is rejected by the server"
        )
    }
}
