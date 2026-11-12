#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class VersionTests: XCTestCase {

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
            "PayCrossSDK-iOS/\(PayCrossAPI.version)"
        )
    }

    func testTheFallbackUserAgentCarriesTheShippedVersion() throws {
        XCTAssertTrue(
            DeviceInfo.defaultUserAgent.contains("PayCrossSDK-iOS/\(PayCrossAPI.version)"),
            "the fallback agent still names a version: \(DeviceInfo.defaultUserAgent)"
        )
    }
}
#endif
