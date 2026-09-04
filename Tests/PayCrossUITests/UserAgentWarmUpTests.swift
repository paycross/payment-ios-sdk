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

    override func setUp() {
        super.setUp()
        original = DeviceInfo.userAgentProvider
    }

    override func tearDown() async throws {
        // Assigning the provider clears anything read from the previous one, so
        // this also resets the cache for the next test.
        DeviceInfo.userAgentProvider = original
        try await super.tearDown()
    }

    /// A provider that never answers, standing in for WebKit that never comes up.
    private static let neverAnswers: UserAgentProvider = {
        await withCheckedContinuation { (_: CheckedContinuation<String?, Never>) in }
    }

    func testTheRealAgentIsUsedWhenItArrives() async {
        DeviceInfo.userAgentProvider = { "Mozilla/5.0 (iPhone) RealAgent/1.0" }

        let agent = await DeviceInfo.userAgent()

        XCTAssertEqual(agent, "Mozilla/5.0 (iPhone) RealAgent/1.0")
    }

    /// The bound is real, and the fallback is usable. The backend validates the
    /// agent non-blank, so an empty one is a rejected payment.
    func testAProviderThatNeverAnswersFallsBackWithinItsBound() async {
        DeviceInfo.userAgentProvider = Self.neverAnswers
        let started = ContinuousClock().now

        let agent = await DeviceInfo.userAgent(timeout: .milliseconds(100))

        XCTAssertEqual(agent, DeviceInfo.defaultUserAgent)
        XCTAssertFalse(agent.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertLessThan(
            ContinuousClock().now - started, .seconds(2),
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
