import XCTest
@testable import PayCrossCore

/// These raw values are the wire vocabulary, agreed verbatim with the Android SDK
/// and the Flutter plugin. A merchant correlating a pending iOS payment with the
/// same payment seen from Android is comparing these exact strings, so renaming
/// one here is a wire break rather than a local rename.
final class PendingReasonTests: XCTestCase {

    func testRawValuesAreTheAgreedWireVocabulary() {
        XCTAssertEqual(PendingReason.pollTimeout.rawValue, "poll_timeout")
        XCTAssertEqual(PendingReason.resultLost.rawValue, "result_lost")
        XCTAssertEqual(PendingReason.serverVerify.rawValue, "server_verify")
    }

    func testEveryReasonRoundTripsThroughItsRawValue() {
        for reason in [PendingReason.pollTimeout, .resultLost, .serverVerify] {
            XCTAssertEqual(PendingReason(rawValue: reason.rawValue), reason)
        }
    }

    /// The vocabulary is exact. A near miss is a bug in whatever produced it, and
    /// must not silently resolve to a neighbouring reason.
    func testNearMissesDoNotParse() {
        XCTAssertNil(PendingReason(rawValue: "POLL_TIMEOUT"))
        XCTAssertNil(PendingReason(rawValue: "poll timeout"))
        XCTAssertNil(PendingReason(rawValue: "pollTimeout"))
        XCTAssertNil(PendingReason(rawValue: ""))
    }
}
