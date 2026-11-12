import XCTest
@testable import PayCrossCore

final class PendingReasonTests: XCTestCase {
    func testRawValuesAreTheAgreedWireVocabulary() {
        XCTAssertEqual(PendingReason.pollTimeout.rawValue, "poll_timeout")
        XCTAssertEqual(PendingReason.resultLost.rawValue, "result_lost")
        XCTAssertEqual(PendingReason.serverVerify.rawValue, "server_verify")
        XCTAssertEqual(
            PendingReason.allCases.count, 3,
            "a new reason needs its string pinned here, and agreed with Android and Dart first"
        )
    }

    func testEveryReasonRoundTripsThroughItsRawValue() {
        for reason in PendingReason.allCases {
            XCTAssertEqual(PendingReason(rawValue: reason.rawValue), reason)
        }
    }

    func testNearMissesDoNotParse() {
        XCTAssertNil(PendingReason(rawValue: "POLL_TIMEOUT"))
        XCTAssertNil(PendingReason(rawValue: "poll timeout"))
        XCTAssertNil(PendingReason(rawValue: "pollTimeout"))
        XCTAssertNil(PendingReason(rawValue: ""))
    }
}
