#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// The user-agent warm-up sits in front of the session fetch, so it must never be
/// the reason a payment sheet has no form.
///
/// `evaluateJavaScript` waits on WebKit's helper processes. On a loaded machine
/// those take tens of seconds to launch, and they may not answer at all — which is
/// what took `ApplePayPresentationTests` down on CI: the two tests that go through
/// `load()` were the only two that failed, and they failed by waiting.
@MainActor
final class UserAgentWarmUpTests: XCTestCase {

    /// The bound is real: with no time allowed, the call still returns promptly
    /// rather than waiting on WebKit.
    func testTheWarmUpGivesUpWhenItsTimeIsSpent() async {
        let started = ContinuousClock().now

        await DeviceInfo.warmUserAgent(timeout: .zero)

        let elapsed = ContinuousClock().now - started
        XCTAssertLessThan(
            elapsed, .seconds(2),
            "a warm-up that outlives its own timeout is a sheet that never opens"
        )
    }

    /// And giving up is safe: the submit body still carries a usable agent, because
    /// the fallback was always there for this.
    func testGivingUpStillLeavesAUsableUserAgent() async {
        await DeviceInfo.warmUserAgent(timeout: .zero)

        let userAgent = DeviceInfo.browserInfo().userAgent
        XCTAssertFalse(
            userAgent.trimmingCharacters(in: .whitespaces).isEmpty,
            "the backend rejects a blank user agent outright"
        )
    }
}
#endif
