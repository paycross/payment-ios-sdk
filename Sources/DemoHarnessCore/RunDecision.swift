import Foundation

public struct PendingRun: Sendable, Equatable {
    public let merchant: Merchant
    public let scenario: Scenario
    public let surface: CheckoutSurface
}

public enum RunDecision: Sendable, Equatable {
    case start(merchant: Merchant, scenario: Scenario, surface: CheckoutSurface)
    case confirmProduction(PendingRun)
    case unresolved(reason: String)
}

public enum HarnessRunner {
    public static func decide(
        merchantName: String,
        scenarioName: String,
        surface: CheckoutSurface,
        in data: DemoData
    ) -> RunDecision {
        guard let merchant = data.merchants.first(where: {
            $0.name.caseInsensitiveCompare(merchantName) == .orderedSame
        }) else {
            return .unresolved(reason: "No merchant named \"\(merchantName)\"")
        }

        guard let scenario = data.scenarios(for: merchant.id).first(where: {
            $0.name.caseInsensitiveCompare(scenarioName) == .orderedSame
        }) else {
            return .unresolved(
                reason: "No scenario named \"\(scenarioName)\" for \(merchant.name)"
            )
        }

        return decide(merchant: merchant, scenario: scenario, surface: surface)
    }

    public static func decide(
        merchant: Merchant,
        scenario: Scenario,
        surface: CheckoutSurface
    ) -> RunDecision {
        guard merchant.isProduction else {
            return .start(merchant: merchant, scenario: scenario, surface: surface)
        }
        return .confirmProduction(
            PendingRun(merchant: merchant, scenario: scenario, surface: surface)
        )
    }
}
