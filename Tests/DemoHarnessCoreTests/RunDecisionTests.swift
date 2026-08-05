import XCTest
@testable import DemoHarnessCore

/// The most valuable test in the harness: a production merchant cannot start a
/// run unconfirmed, including from the deep link that no view sees.
final class RunDecisionTests: XCTestCase {

    private let sandbox = Merchant(id: "m1", name: "Sandbox merchant", environment: .staging)
    private let live = Merchant(id: "m2", name: "LIVE merchant", environment: .production)

    private var data: DemoData {
        DemoData(
            merchants: [sandbox, live],
            scenarios: [
                Scenario(id: "s1", merchantID: "m1", name: "Approve", requestBody: "{}"),
                Scenario(id: "s2", merchantID: "m2", name: "Approve", requestBody: "{}")
            ]
        )
    }

    // MARK: - The gate

    func testStagingRunsStartImmediately() {
        let decision = HarnessRunner.decide(
            merchantName: "Sandbox merchant", scenarioName: "Approve",
            surface: .sdk, in: data
        )
        guard case .start(let merchant, let scenario, let surface) = decision else {
            return XCTFail("expected .start, got \(decision)")
        }
        XCTAssertEqual(merchant.id, "m1")
        XCTAssertEqual(scenario.id, "s1")
        XCTAssertEqual(surface, .sdk)
    }

    func testProductionRunsRequireConfirmation() {
        let decision = HarnessRunner.decide(
            merchantName: "LIVE merchant", scenarioName: "Approve",
            surface: .sdk, in: data
        )
        guard case .confirmProduction(let pending) = decision else {
            return XCTFail("a production run must not start unconfirmed, got \(decision)")
        }
        XCTAssertEqual(pending.merchant.id, "m2")
        XCTAssertEqual(pending.scenario.id, "s2")
    }

    /// The dangerous path: `xcrun simctl openurl` with no human present. A gate
    /// implemented in a view would not cover this.
    func testProductionIsGatedOnEverySurfaceIncludingTheDeepLink() {
        for surface in CheckoutSurface.allCases {
            let decision = HarnessRunner.decide(
                merchantName: "LIVE merchant", scenarioName: "Approve",
                surface: surface, in: data
            )
            guard case .confirmProduction = decision else {
                return XCTFail("\(surface) started a production run unconfirmed")
            }
        }
    }

    /// Same gate whether the run came from the UI or a URL.
    func testDirectDecideGatesProductionToo() {
        let scenario = Scenario(merchantID: "m2", name: "Approve", requestBody: "{}")
        guard case .confirmProduction = HarnessRunner.decide(
            merchant: live, scenario: scenario, surface: .sdk
        ) else {
            return XCTFail("the UI path must use the same gate")
        }
        guard case .start = HarnessRunner.decide(
            merchant: sandbox, scenario: scenario, surface: .sdk
        ) else {
            return XCTFail("staging should not be gated")
        }
    }

    // MARK: - Resolution

    /// Scenarios are namespaced per merchant; both merchants here have an
    /// "Approve", and the wrong one would run against production.
    func testScenariosResolveWithinTheNamedMerchant() {
        guard case .start(_, let scenario, _) = HarnessRunner.decide(
            merchantName: "Sandbox merchant", scenarioName: "Approve",
            surface: .sdk, in: data
        ) else {
            return XCTFail("expected .start")
        }
        XCTAssertEqual(scenario.id, "s1", "picked another merchant's scenario")
    }

    func testUnknownNamesAreReportedRatherThanIgnored() {
        guard case .unresolved(let reason) = HarnessRunner.decide(
            merchantName: "Nope", scenarioName: "Approve", surface: .sdk, in: data
        ) else {
            return XCTFail("expected .unresolved")
        }
        XCTAssertTrue(reason.contains("Nope"), "the reason must name what was not found")

        guard case .unresolved(let scenarioReason) = HarnessRunner.decide(
            merchantName: "Sandbox merchant", scenarioName: "Nope",
            surface: .sdk, in: data
        ) else {
            return XCTFail("expected .unresolved")
        }
        XCTAssertTrue(scenarioReason.contains("Nope"))
    }

    func testNameMatchingIsCaseInsensitive() {
        guard case .start = HarnessRunner.decide(
            merchantName: "sandbox MERCHANT", scenarioName: "approve",
            surface: .sdk, in: data
        ) else {
            return XCTFail("a runner should not have to match case exactly")
        }
    }

    func testEmptyHarnessResolvesToNothingRatherThanCrashing() {
        guard case .unresolved = HarnessRunner.decide(
            merchantName: "Any", scenarioName: "Any", surface: .sdk, in: DemoData()
        ) else {
            return XCTFail("expected .unresolved")
        }
    }
}
