#if os(iOS)
import XCTest
@testable import PayCross
@testable import PayCrossCore

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
        DeviceInfo.userAgentProvider = original
        DeviceInfo.boundedWait = originalBoundedWait
        try await super.tearDown()
    }

    private static let neverAnswers: UserAgentProvider = {
        await withCheckedContinuation { (_: CheckedContinuation<String?, Never>) in }
    }

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
