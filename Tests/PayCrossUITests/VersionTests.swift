#if os(iOS)
import XCTest
@testable import PayCross

/// The version in the User-Agent must be the version the merchant installed.
///
/// It was `0.1.0-alpha` while the pods shipped `0.1.1`, so every payment made
/// through this SDK told the backend it came from a version that was never
/// released. That is not cosmetic: the User-Agent is how a support question
/// about one merchant's payments gets narrowed to one SDK build.
final class VersionTests: XCTestCase {

    /// Read from the podspec rather than restated here. A test that repeats
    /// the literal is a second place to edit at the next release and catches
    /// nothing that reading the diff would not.
    private func podspecVersion() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PayCrossUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let podspec = try String(contentsOf: root.appendingPathComponent("PayCross.podspec"), encoding: .utf8)

        let pattern = try NSRegularExpression(pattern: #"s\.version\s*=\s*'([^']+)'"#)
        let range = NSRange(podspec.startIndex..., in: podspec)
        let match = try XCTUnwrap(pattern.firstMatch(in: podspec, range: range))

        return String(podspec[try XCTUnwrap(Range(match.range(at: 1), in: podspec))])
    }

    func testTheVersionMatchesThePodspec() throws {
        XCTAssertEqual(PayCrossAPI.version, try podspecVersion())
    }

    /// The same comparison from the other end: the string the API client
    /// actually sends is built by interpolating the constant, so pinning the
    /// interpolation against the podspec catches a version that is right in
    /// isolation and wrong on the wire.
    func testTheUserAgentCarriesTheShippedVersion() throws {
        XCTAssertEqual(
            "PayCrossSDK-iOS/\(PayCrossAPI.version)",
            "PayCrossSDK-iOS/\(try podspecVersion())"
        )
    }
}
#endif
