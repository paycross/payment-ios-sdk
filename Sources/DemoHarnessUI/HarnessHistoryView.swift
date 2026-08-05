#if os(iOS)
import SwiftUI
import DemoHarnessCore

/// Every session this harness has minted, newest first.
///
/// History exists because the interesting failures are the ones you notice after
/// the fact: a run that reported success but took no money, or a scenario that
/// behaves differently on the browser surface than in the sheet.
public struct HarnessHistoryView: View {
    let runs: [RunRecord]
    let onSelect: (RunRecord) -> Void

    public init(runs: [RunRecord], onSelect: @escaping (RunRecord) -> Void) {
        self.runs = runs
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if runs.isEmpty {
                // Hand-rolled rather than ContentUnavailableView, which is iOS 17+
                // while this package targets iOS 16.
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No runs yet")
                        .font(.headline)
                    Text("Sessions you mint will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(runs) { run in
                    Button { onSelect(run) } label: { RunRow(run: run) }
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct RunRow: View {
    let run: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.scenarioName)
                    .foregroundStyle(.primary)
                Spacer()
                OutcomeBadge(outcome: run.outcome)
            }
            HStack(spacing: 6) {
                Text(run.surface.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                if let amount = run.amount, let currency = run.currency {
                    Text("\(amount) \(currency)").monospacedDigit()
                }
                Text(run.sessionID.isEmpty ? "—" : run.sessionID)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// State is carried by shape and text, not colour alone, so it survives a
/// colour-blind reader and a greyscale screenshot.
private struct OutcomeBadge: View {
    let outcome: String

    private var appearance: (symbol: String, tint: Color) {
        switch outcome {
        case "succeeded": ("checkmark.circle.fill", Color(.systemGreen))
        case RunRecord.pendingOutcome: ("clock", Color(.systemGray))
        default:
            outcome.hasPrefix("unresolved")
                ? ("questionmark.circle.fill", Color(.systemOrange))
                : ("xmark.circle.fill", Color(.systemRed))
        }
    }

    var body: some View {
        Label(outcome, systemImage: appearance.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(appearance.tint)
            .labelStyle(.titleAndIcon)
    }
}

/// One run in full, including the exact body that was posted.
public struct RunDetailView: View {
    let run: RunRecord
    let curlCommand: String
    let onCopyCurl: () -> Void

    public init(run: RunRecord, curlCommand: String, onCopyCurl: @escaping () -> Void) {
        self.run = run
        self.curlCommand = curlCommand
        self.onCopyCurl = onCopyCurl
    }

    public var body: some View {
        List {
            Section("Outcome") {
                LabeledContent("Status", value: run.outcome)
                if let transactionID = run.transactionID {
                    LabeledContent("Transaction", value: transactionID)
                }
                if let amount = run.amount, let currency = run.currency {
                    LabeledContent("Amount", value: "\(amount) \(currency)")
                }
                LabeledContent("Surface", value: run.surface.rawValue)
            }

            Section("Session") {
                LabeledContent("ID", value: run.sessionID)
                if !run.checkoutURL.isEmpty {
                    LabeledContent("Checkout", value: run.checkoutURL)
                }
            }

            Section("Request body") {
                Text(run.requestBody)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section {
                Button("Copy curl to reproduce", action: onCopyCurl)
            } footer: {
                Text("Credentials are read from environment variables, not embedded.")
            }
        }
        .navigationTitle(run.scenarioName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
