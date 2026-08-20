import Foundation

/// A run that is waiting for the tester to confirm it.
public struct PendingRun: Sendable, Equatable {
    public let merchant: Merchant
    public let scenario: Scenario
    public let surface: CheckoutSurface
}

/// What should happen when something asks to run a scenario.
public enum RunDecision: Sendable, Equatable {
    case start(merchant: Merchant, scenario: Scenario, surface: CheckoutSurface)
    /// Production. Nothing may be minted until a human confirms.
    case confirmProduction(PendingRun)
    /// The named merchant or scenario does not exist.
    case unresolved(reason: String)
}

/// Resolves a run request and decides whether it needs confirmation.
///
/// In Core, not in a view, for one reason: the deep-link entry point
/// (`paycross-demo://run?...`) does not go through any view. A gate implemented
/// in SwiftUI would leave an `xcrun simctl openurl` runner able to start a
/// PRODUCTION payment with no human present. Android routes all three entry
/// points — the scenario list, the external-surface path and the deep link —
/// through one gate for the same reason (`DemoViewModel.kt:178-186`).
public enum HarnessRunner {

    /// Resolves by NAME, because that is what the deep-link contract carries: a
    /// runner is written against the seeds without reading device storage.
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

    /// The same gate for a run started from the UI, where both are already known.
    public static func decide(
        merchant: Merchant,
        scenario: Scenario,
        surface: CheckoutSurface
    ) -> RunDecision {
        guard merchant.isProduction else {
            return .start(merchant: merchant, scenario: scenario, surface: surface)
        }
        // Deliberately BEFORE any minting. A confirmation shown after the session
        // exists has already spent real money's worth of setup.
        return .confirmProduction(
            PendingRun(merchant: merchant, scenario: scenario, surface: surface)
        )
    }
}
