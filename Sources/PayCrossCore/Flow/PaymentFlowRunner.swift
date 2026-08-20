import Foundation

/// Presents a 3DS step and reports how it ended.
///
/// The runner lives in Core, so the thing that actually shows a web view is a
/// protocol. That is what lets the whole payment sequence — submit, retry-after,
/// poll, 3DS, terminal — run under `swift test` on Linux.
package protocol ThreeDSPresenting: Sendable {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome
    func dismiss() async
}

package enum ThreeDSOutcome: Sendable, Equatable {
    case completed
    case failed
}

/// Time, injected. The real one sleeps; the test one advances a counter, so an
/// 8-minute deadline is asserted in microseconds.
package protocol FlowScheduler: Sendable {
    func sleep(for duration: Duration) async throws
    /// Monotonic time consumed since this scheduler was created.
    func elapsed() async -> Duration
}

package actor ContinuousScheduler: FlowScheduler {
    private let start = ContinuousClock().now

    package init() {}

    package func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }

    package func elapsed() async -> Duration {
        ContinuousClock().now - start
    }
}

/// How a run ended.
package enum FlowOutcome: Sendable, Equatable {
    /// The payment reached a terminal state.
    case finished(PaymentResult)
    /// The form should be re-armed with this message, and the user may try again.
    case reArmForm(message: String)
}

/// Drives a payment from submission to a terminal state.
///
/// Sequencing only — every decision about *what a status means* belongs to
/// `PaymentFlowReducer`, which is a pure function.
package actor PaymentFlowRunner {
    private let client: PayCrossAPIClient
    private let presenter: any ThreeDSPresenting
    private let scheduler: any FlowScheduler
    private var state: PaymentFlowState
    private var presentationTask: Task<Void, Never>?
    /// The server's last rejection text, for diagnostics. Never shown to a
    /// shopper -- it can name internal fields.
    package private(set) var lastServerDiagnostic: String?

    package init(
        client: PayCrossAPIClient,
        presenter: any ThreeDSPresenting,
        scheduler: any FlowScheduler = ContinuousScheduler(),
        claims: SessionClaims? = nil
    ) {
        self.client = client
        self.presenter = presenter
        self.scheduler = scheduler
        self.state = PaymentFlowState(claims: claims)
    }

    package func currentState() -> PaymentFlowState { state }

    /// Polls an existing transaction to its terminal state without submitting.
    ///
    /// Used when the session already has one in flight - the shopper backgrounded
    /// the app mid-3DS, or the sheet was re-presented. Submitting again would
    /// create a second transaction against the same session.
    package func resume(transactionID: String) async -> FlowOutcome {
        state.transactionID = transactionID
        return await poll(transactionID: transactionID)
    }

    /// Submits a card and runs the flow to a terminal state.
    package func run(_ request: SubmitCardRequest) async -> FlowOutcome {
        switch await submitWithRetry(request) {
        case .failure(let message):
            return .reArmForm(message: message)
        case .success(let transactionID):
            state.transactionID = transactionID
            return await poll(transactionID: transactionID)
        }
    }

    // MARK: - Submit

    private enum SubmitResult {
        case success(String)
        case failure(String)
    }

    /// One idempotency key for the whole loop, so a retry cannot authorize twice.
    private func submitWithRetry(_ request: SubmitCardRequest) async -> SubmitResult {
        let idempotencyKey = client.newIdempotencyKey()

        for _ in 0..<FlowLimits.maxSubmitAttempts {
            let response: SubmitCardResponse
            do {
                response = try await client.submitCard(request, idempotencyKey: idempotencyKey)
            } catch let error as PayCrossError {
                // Android does not retry a transport or HTTP failure here: the
                // request may already have been received.
                if case .transport = error {
                    return .failure("Network error. Please try again.")
                }
                // The server's own message is kept as a diagnostic rather than
                // collapsed to a generic string. Swallowing it is why an SDK
                // that could never submit -- every request rejected for
                // "missing browser_info.ip_address" -- looked like a plain
                // decline for its entire development.
                lastServerDiagnostic = error.serverMessage
                return .failure("Payment submission failed")
            } catch {
                return .failure("Network error. Please try again.")
            }

            if response.success == true, let transactionID = response.transactionID {
                return .success(transactionID)
            }

            guard let retryAfter = response.retryAfter else {
                return .failure(response.error ?? "Payment submission failed")
            }

            try? await scheduler.sleep(for: .seconds(retryAfter))
        }

        return .failure("Payment submission failed")
    }

    // MARK: - Poll

    private func poll(transactionID: String) async -> FlowOutcome {
        state.isPolling = true
        // Measured from the START of polling, not from the runner's construction.
        // Android computes its deadline inside pollStatus (PaymentViewModel.kt:266)
        // so the retry-after loop cannot eat the budget. Server-controlled
        // retry_after values are uncapped, so four 120s replies would otherwise
        // consume all 480s and the loop would run ZERO iterations - reporting
        // failure for a transaction that was created and may be authorized.
        let start = await scheduler.elapsed()

        while await scheduler.elapsed() - start < FlowLimits.pollDeadline {
            do {
                let status = try await client.status(transactionID: transactionID)
                let effects = PaymentFlowReducer.reduce(
                    state: &state,
                    event: .statusReceived(status)
                )
                if let outcome = await apply(effects) {
                    return outcome
                }
            } catch {
                // The status item may not exist yet, or polling may be throttled.
                // Both are transient; keep going until the deadline.
            }

            try? await scheduler.sleep(for: FlowLimits.pollInterval)
        }

        let effects = PaymentFlowReducer.reduce(state: &state, event: .pollDeadlineReached)
        return await apply(effects) ?? .finished(.failed(transactionID: transactionID, recovery: .retry))
    }

    /// Called when a presented 3DS step resolves.
    ///
    /// Both outcomes are handled identically on purpose: a failed challenge is
    /// not terminal, because the server owns the verdict and polling is what
    /// surfaces it. The outcome is taken as a parameter rather than dropped so
    /// the protocol's contract stays honest, and the reducer's effects are
    /// applied rather than discarded — that is what dismisses the web view.
    private func threeDSResolved(_ outcome: ThreeDSOutcome) async {
        let effects = PaymentFlowReducer.reduce(state: &state, event: .threeDSCompleted)
        _ = await apply(effects)
    }

    /// Runs the reducer's effects. Returns an outcome when the run is over.
    ///
    /// `stopPolling` without a `finish` is the retryable-decline case: the loop
    /// ends and the form is re-armed, but no result is delivered.
    private func apply(_ effects: [PaymentFlowEffect]) async -> FlowOutcome? {
        var outcome: FlowOutcome?

        for effect in effects {
            switch effect {
            case .dismiss3DS:
                await presenter.dismiss()

            case .present3DS(let step):
                // Deliberately NOT awaited. Android's handleStatus sets the 3DS
                // state and returns false, so polling keeps running while the
                // challenge is on screen - the server decides the outcome, not
                // the web view. Awaiting here would stall the poll loop for as
                // long as the shopper takes to answer their bank.
                presentationTask?.cancel()
                presentationTask = Task { [presenter] in
                    let outcome = await presenter.present(step)
                    // A superseded or abandoned step must not act on its late
                    // outcome: its teardown already happened when it was
                    // cancelled, and applying `.threeDSCompleted` here would
                    // dismiss whatever step replaced it.
                    guard !Task.isCancelled else { return }
                    await self.threeDSResolved(outcome)
                }

            case .finish(let result):
                // Nothing is waiting on a presented step once the flow is over.
                presentationTask?.cancel()
                presentationTask = nil
                outcome = .finished(result)

            case .stopPolling:
                state.isPolling = false
                if outcome == nil {
                    outcome = .reArmForm(message: state.inlineError ?? "Payment failed. Please try again.")
                }
            }
        }

        // A finish always wins over a re-arm produced by the same batch.
        if case .some(.reArmForm) = outcome, state.result != nil {
            return .finished(state.result!)
        }
        return outcome
    }
}
