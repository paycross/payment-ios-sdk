#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// The version in the User-Agent must be the version the merchant installed.
///
/// It was `0.1.0-alpha` while the pods shipped `0.1.1`, so every payment made
/// through this SDK told the backend it came from a version that was never
/// released. That is not cosmetic: the User-Agent is how a support question
/// about one merchant's payments gets narrowed to one SDK build.
@MainActor
final class VersionTests: XCTestCase {

    /// Read from the podspecs rather than restated here. A test that repeats
    /// the literal is a second place to edit at the next release and catches
    /// nothing that reading the diff would not.
    ///
    /// Both podspecs, because `PayCross.podspec` declares
    /// `s.dependency 'PayCrossCore', "#{s.version}"`: bump one and not the
    /// other and nothing fails until `pod lib lint` refuses at publish time,
    /// with the version already chosen.
    private func podspecVersion(_ name: String = "PayCross") throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PayCrossUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
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

    /// The same comparison from the far end: the byte that actually goes on the
    /// wire.
    ///
    /// An earlier version of this test compared the constant to itself, with
    /// the same interpolated prefix on both sides, so it could not fail
    /// independently of the test above and never read a shipped string at all.
    /// This drives a real session fetch through a stub transport and reads the
    /// header off the request the client built.
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

    /// The fallback User-Agent is a shipped string too: it is what a 3DS
    /// submission carries until the real device agent resolves.
    func testTheFallbackUserAgentCarriesTheShippedVersion() throws {
        XCTAssertTrue(
            DeviceInfo.defaultUserAgent.contains("PayCrossSDK-iOS/\(try podspecVersion())"),
            "the fallback agent still names a version: \(DeviceInfo.defaultUserAgent)"
        )
    }
}
#endif
