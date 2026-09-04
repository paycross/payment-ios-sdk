import XCTest
@testable import PayCrossCore

final class RecoveryTests: XCTestCase {

    func testKnownValuesParse() {
        XCTAssertEqual(Recovery(apiValue: "retry"), .retry)
        XCTAssertEqual(Recovery(apiValue: "change_method"), .changeMethod)
        XCTAssertEqual(Recovery(apiValue: "restart"), .restart)
        XCTAssertEqual(Recovery(apiValue: "contact_support"), .contactSupport)
        XCTAssertEqual(Recovery(apiValue: "contact_us"), .contactSupport)
        XCTAssertEqual(Recovery(apiValue: "do_not_retry"), .doNotRetry)
        XCTAssertEqual(Recovery(apiValue: "verify_before_retry"), .verifyBeforeRetry)
    }

    func testParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(Recovery(apiValue: "  DO_NOT_RETRY \n"), .doNotRetry)
        XCTAssertEqual(Recovery(apiValue: "Change_Method"), .changeMethod)
    }

    /// Android: absent values default to RETRY.
    func testAbsentAndEmptyDefaultToRetry() {
        XCTAssertEqual(Recovery(apiValue: nil), .retry)
        XCTAssertEqual(Recovery(apiValue: ""), .retry)
        XCTAssertEqual(Recovery(apiValue: "   "), .retry)
    }

    /// The whole point of the type: an unknown server value must not be retryable.
    func testUnknownValuesFailClosed() {
        let recovery = Recovery(apiValue: "some_future_value")
        XCTAssertEqual(recovery, .unrecognized("some_future_value"))
        XCTAssertFalse(recovery.isRetryable)
        XCTAssertFalse(recovery.isRecognized)
    }

    func testRetryabilityIsAWhitelist() {
        XCTAssertTrue(Recovery.retry.isRetryable)
        XCTAssertTrue(Recovery.changeMethod.isRetryable)
        XCTAssertFalse(Recovery.restart.isRetryable)
        XCTAssertFalse(Recovery.contactSupport.isRetryable)
        XCTAssertFalse(Recovery.doNotRetry.isRetryable)
        XCTAssertFalse(Recovery.unrecognized("x").isRetryable)
        XCTAssertFalse(
            Recovery.verifyBeforeRetry.isRetryable,
            "an outcome nobody observed is the one case that must never be retried"
        )
    }

    /// It is a value this SDK understands, unlike `unrecognized`. A merchant
    /// telling the two apart is the difference between "check this transaction"
    /// and "upgrade the SDK".
    func testVerifyBeforeRetryIsARecognizedValue() {
        XCTAssertTrue(Recovery.verifyBeforeRetry.isRecognized)
    }

    /// Guards the reason Recovery is not RawRepresentable: a synthesised
    /// init?(rawValue:) would be a fail-open parser next to the fail-closed one.
    func testUnrecognizedPreservesRawValueForTelemetry() {
        guard case .unrecognized(let raw) = Recovery(apiValue: "Weird_Value") else {
            return XCTFail("expected .unrecognized")
        }
        XCTAssertEqual(raw, "weird_value")
    }
}
