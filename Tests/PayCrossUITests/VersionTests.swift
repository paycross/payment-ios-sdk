#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class VersionTests: XCTestCase {

    private func podspecVersion(_ name: String = "PayCross") throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let podspec = try String(
            contentsOf: root.appendingPathComponent("\(name).podspec"), encoding: .utf8
        )

        let pattern = try NSRegularExpression(pattern: #"s\.version\s*=\s*'([^']+)'"#)
        let range = NSRange(podspec.startIndex..., in: podspec)
        let match = try XCTUnwrap(pattern.firstMatch(in: podspec, range: range))

        return String(podspec[try XCTUnwrap(Range(match.range(at: 1), in: podspec))])
    }

    func testTheVersionMatchesThePodspec() throws {
        XCTAssertEqual(PayCrossAPI.version, try podspecVersion())
    }

    func testBothPodspecsShipTheSameVersion() throws {
        XCTAssertEqual(
            try podspecVersion("PayCrossCore"), try podspecVersion("PayCross"),
            "PayCross depends on PayCrossCore at its own version; bumping one alone fails at publish"
        )
    }

    func testTheHeaderOnTheWireCarriesTheShippedVersion() async throws {
        let transport = StubTransport(json: #"{"session_id":"sess_1","status":"open"}"#)
        let model = PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1", brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
            ),
            configuration: Configuration(
                environment: .sandbox, testCardPrefill: nil, applePayMerchantIdentifier: nil
            ),
            transport: transport
        )

        await model.load()

        let sent = await transport.sent
        let request = try XCTUnwrap(sent.first, "the session was never fetched")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "PayCrossSDK-iOS/\(try podspecVersion())"
        )
    }

    func testTheFallbackUserAgentCarriesTheShippedVersion() throws {
        XCTAssertTrue(
            DeviceInfo.defaultUserAgent.contains("PayCrossSDK-iOS/\(try podspecVersion())"),
            "the fallback agent still names a version: \(DeviceInfo.defaultUserAgent)"
        )
    }
}
#endif
