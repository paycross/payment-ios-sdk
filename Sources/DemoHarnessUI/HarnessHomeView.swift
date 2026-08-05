#if os(iOS)
import SwiftUI
import DemoHarnessCore

/// The harness home screen: pick a merchant, pick a scenario, pick a surface, run.
///
/// The surface choice is the point of this app. A teammate wanted to show the
/// payment page in a browser rather than in the app, so minting, presenting and
/// observing are deliberately decoupled — the outcome comes from polling the
/// session regardless of where the shopper actually paid.
public struct HarnessHomeView: View {
    @Binding var data: DemoData
    @Binding var surface: CheckoutSurface
    let onRun: (Scenario, CheckoutSurface) -> Void
    let onShowHistory: () -> Void

    public init(
        data: Binding<DemoData>,
        surface: Binding<CheckoutSurface>,
        onRun: @escaping (Scenario, CheckoutSurface) -> Void,
        onShowHistory: @escaping () -> Void
    ) {
        self._data = data
        self._surface = surface
        self.onRun = onRun
        self.onShowHistory = onShowHistory
    }

    private var merchant: Merchant? {
        data.merchants.first { $0.id == data.selectedMerchantID } ?? data.merchants.first
    }

    private var scenarios: [Scenario] {
        merchant.map { data.scenarios(for: $0.id) } ?? []
    }

    public var body: some View {
        List {
            Section("Merchant") {
                Picker("Merchant", selection: merchantSelection) {
                    ForEach(data.merchants) { merchant in
                        Text(merchant.name).tag(merchant.id)
                    }
                }
                .pickerStyle(.menu)

                if let merchant, merchant.isProduction {
                    ProductionWarning()
                }
            }

            Section("Surface") {
                Picker("Surface", selection: $surface) {
                    Text("SDK sheet").tag(CheckoutSurface.sdk)
                    Text("Browser").tag(CheckoutSurface.browser)
                    Text("Link").tag(CheckoutSurface.link)
                    Text("QR").tag(CheckoutSurface.qr)
                }
                .pickerStyle(.segmented)

                Text(surfaceExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Scenarios") {
                if scenarios.isEmpty {
                    Text("No scenarios for this merchant yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scenarios) { scenario in
                        ScenarioRow(scenario: scenario) { onRun(scenario, surface) }
                    }
                }
            }

            Section {
                Button(action: onShowHistory) {
                    HStack {
                        Text("Run history")
                        Spacer()
                        Text("\(data.runs.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("PayCross Harness")
    }

    private var merchantSelection: Binding<String> {
        Binding(
            get: { merchant?.id ?? "" },
            set: { data.selectedMerchantID = $0 }
        )
    }

    private var surfaceExplanation: String {
        switch surface {
        case .sdk: "Presents the native payment sheet in this app."
        case .browser: "Opens the hosted checkout page in a browser and polls for the outcome."
        case .link: "Copies a checkout link. Open it anywhere; the outcome still lands here."
        case .qr: "Shows a QR code to scan on another device."
        }
    }
}

/// Production is a different colour and says so in words, never colour alone.
private struct ProductionWarning: View {
    var body: some View {
        Label {
            Text("Production — real money. Runs require confirmation.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(Color(.systemOrange))
    }
}

private struct ScenarioRow: View {
    let scenario: Scenario
    let onRun: () -> Void

    var body: some View {
        Button(action: onRun) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scenario.name)
                    .foregroundStyle(.primary)
                if let hint = scenario.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if scenario.card.isUsable {
                    Text("•••• \(String(scenario.card.pan.suffix(4)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("scenario-\(scenario.name)")
    }
}

/// The confirmation gate for production runs.
///
/// It must be answered BEFORE anything is minted — a gate that fires after the
/// session exists has already spent real money's worth of setup. This is the
/// exact defect a review found in the Android harness.
public struct ProductionGateView: View {
    let merchantName: String
    let scenarioName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(
        merchantName: String,
        scenarioName: String,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.merchantName = merchantName
        self.scenarioName = scenarioName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color(.systemOrange))
            Text("Run against production?")
                .font(.headline)
            Text("\(scenarioName) on \(merchantName). This charges a real card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
                Button("Run it", action: onConfirm)
                    .frame(maxWidth: .infinity)
                    .tint(Color(.systemOrange))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
#endif
