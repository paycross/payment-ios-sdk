#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

/// The user agent must never be able to stop the sheet.
///
/// It is read out of a `WKWebView`, and `evaluateJavaScript` waits on WebKit's
/// helper processes: on a loaded machine those take tens of seconds to launch, and
/// they need not answer at all. `load()` used to await that read before fetching
/// the session, so the form was gated on WebKit — which is what took
/// `ApplePayPresentationTests` down on CI, and what would leave a shopper on a
/// spinner on a device whose WebKit is slow to start.
///
/// Every case here injects its provider. None of them touch WebKit, which is the
/// point: a test that depends on WebKit launching is the defect, not the cover.
@MainActor
final class UserAgentWarmUpTests: XCTestCase {

    private var original: UserAgentProvider!
    private var originalBoundedWait: BoundedWait!

    override func setUp() async throws {
        try await super.setUp()
        original = DeviceInfo.userAgentProvider
        originalBoundedWait = DeviceInfo.boundedWait
    }

    override func tearDown() async throws {
        // Assigning the provider clears anything read from the previous one, so
        // this also resets the cache for the next test.
        DeviceInfo.userAgentProvider = original
        DeviceInfo.boundedWait = originalBoundedWait
        try await super.tearDown()
    }

    /// A provider that never answers, standing in for WebKit that never comes up.
    private static let neverAnswers: UserAgentProvider = {
        await withCheckedContinuation { (_: CheckedContinuation<String?, Never>) in }
    }

    /// The read's bound, driven by hand instead of by a clock.
    ///
    /// Records the duration it was handed, reports when the read has reached it,
    /// and holds there until the test says the bound has elapsed.
    private actor ManualBound {
        private(set) var requested: Duration?
        private var reached = false
        private var arrival: CheckedContinuation<Void, Never>?
        private var elapsed: CheckedContinuation<Void, Never>?

        func wait(_ duration: Duration) async {
            requested = duration
            reached = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { elapsed = $0 }
        }

        func hasBeenReached() async {
            guard !reached else { return }
            await withCheckedContinuation { arrival = $0 }
        }

        func elapse() {
            elapsed?.resume()
            elapsed = nil
        }
    }

    func testTheRealAgentIsUsedWhenItArrives() async {
        DeviceInfo.userAgentProvider = { "Mozilla/5.0 (iPhone) RealAgent/1.0" }

        let agent = await DeviceInfo.userAgent()

        XCTAssertEqual(agent, "Mozilla/5.0 (iPhone) RealAgent/1.0")
    }

    /// The bound is real, and the fallback is usable. The backend validates the
    /// agent non-blank, so an empty one is a rejected payment.
    ///
    /// Driven rather than timed. A stopwatch made this a coin toss on a loaded
    /// runner — a 100ms bound measured 2.24s against a 2s assertion — and it could
    /// not tell a read that ended because its bound elapsed from one that ended
    /// for some other reason. Releasing the bound by hand pins both: the read is
    /// waiting on its bound and nothing else, and the duration it waits on is the
    /// caller's own, which no elapsed time could establish.
    func testAProviderThatNeverAnswersFallsBackWithinItsBound() async {
        DeviceInfo.userAgentProvider = Self.neverAnswers
        let bound = ManualBound()
        DeviceInfo.boundedWait = { await bound.wait($0) }

        async let read = DeviceInfo.userAgent(timeout: .milliseconds(100))
        await bound.hasBeenReached()
        await bound.elapse()
        let agent = await read

        XCTAssertEqual(agent, DeviceInfo.defaultUserAgent)
        XCTAssertFalse(
            agent.trimmingCharacters(in: .whitespaces).isEmpty,
            "the backend rejects a blank user agent outright"
        )
        let waitedOn = await bound.requested
        XCTAssertEqual(
            waitedOn, .milliseconds(100),
            "a read that outlives its own bound is a shopper waiting on nothing"
        )
    }

    func testTheSubmitBodyCarriesTheAgentTheProviderGave() async {
        DeviceInfo.userAgentProvider = { "Mozilla/5.0 (iPhone) RealAgent/1.0" }

        let info = await DeviceInfo.browserInfo()

        XCTAssertEqual(info.userAgent, "Mozilla/5.0 (iPhone) RealAgent/1.0")
    }

    /// The regression itself, and the reason this file exists: the session has to
    /// reach the model even when the user agent never will.
    func testTheSessionLoadsWhileTheUserAgentNeverAnswers() async {
        DeviceInfo.userAgentProvider = Self.neverAnswers

        let model = PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                expiresAt: nil
            ),
            configuration: Configuration(
                environment: .sandbox, testCardPrefill: nil,
                applePayMerchantIdentifier: "merchant.pay-cross.com"
            ),
            walletAuthorizer: nil,
            deviceCanPay: { true },
            sessionData: nil,
            isPreparing: true,
            transport: StubTransport(json: #"""
                {"session_id":"sess_1","status":"open",
                 "data":{"merchant_country":"GB","wallets":{"apple_pay":true}}}
                """#)
        )

        await model.load()

        XCTAssertNotNil(
            model.sessionData,
            "the form must not be gated on a user agent that never arrives"
        )
        XCTAssertFalse(model.isPreparing)
    }
}
#endif
