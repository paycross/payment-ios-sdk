import Foundation

package protocol ThreeDSPresenting: Sendable {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome
    func dismiss() async
}

package enum ThreeDSOutcome: Sendable, Equatable {
    case completed
    case failed
}

package protocol FlowScheduler: Sendable {
    func sleep(for duration: Duration) async throws
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

package enum FlowOutcome: Sendable, Equatable {
    case finished(PaymentResult)
    case reArmForm(message: String)
}

package actor PaymentFlowRunner {
    private let client: PayCrossAPIClient
    private let presenter: any ThreeDSPresenting
    private let scheduler: any FlowScheduler
    private var state: PaymentFlowState
    private var presentationTask: Task<Void, Never>?
    /// The server's last rejection text. Never shown to the shopper, as it can name internal fields.
    package private(set) var lastServerDiagnostic: String?

    /// Called with the transaction id as soon as the flow has one.
    private let onTransactionID: @Sendable (String) async -> Void

    private let messages: FlowMessages

    package init(
        client: PayCrossAPIClient,
        presenter: any ThreeDSPresenting,
        scheduler: any FlowScheduler = ContinuousScheduler(),
        claims: SessionClaims? = nil,
        messages: FlowMessages = .english,
        onTransactionID: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.client = client
        self.presenter = presenter
        self.scheduler = scheduler
        self.state = PaymentFlowState(claims: claims)
        self.messages = messages
        self.onTransactionID = onTransactionID
    }

    package func currentState() -> PaymentFlowState { state }

    /// Polls an existing transaction to its terminal state without submitting it again.
    package func resume(transactionID: String) async -> FlowOutcome {
        state.transactionID = transactionID
        await onTransactionID(transactionID)
        return await poll(transactionID: transactionID)
    }

    package func run(_ request: SubmitCardRequest) async -> FlowOutcome {
        switch await submitWithRetry(request) {
        case .failure(let message):
            return .reArmForm(message: message)
        case .cancelled:
            return await stopped()
        case .success(let transactionID):
            state.transactionID = transactionID
            await onTransactionID(transactionID)
            return await poll(transactionID: transactionID)
        }
    }

    // MARK: - Submit

    private enum SubmitResult {
        case success(String)
        case failure(String)
        case cancelled
    }

    private func submitWithRetry(_ request: SubmitCardRequest) async -> SubmitResult {
        let idempotencyKey = client.newIdempotencyKey()

        for _ in 0..<FlowLimits.maxSubmitAttempts {
            if Task.isCancelled { return .cancelled }

            let response: SubmitCardResponse
            do {
                response = try await client.submitCard(request, idempotencyKey: idempotencyKey)
            } catch let error as PayCrossError {
                // Not retried: the request may already have been received.
                if case .transport = error {
                    return .failure(messages.networkError)
                }
                lastServerDiagnostic = error.serverMessage
                return .failure(messages.submissionFailed)
            } catch {
                return .failure(messages.networkError)
            }

            if response.success == true, let transactionID = response.transactionID {
                return .success(transactionID)
            }

            guard let retryAfter = response.retryAfter else {
                return .failure(response.error ?? messages.submissionFailed)
            }

            // retry_after is uncapped from the server, and cancellation must be observed here.
            do {
                try await scheduler.sleep(for: .seconds(retryAfter))
            } catch {
                return .cancelled
            }
        }

        return .failure(messages.submissionFailed)
    }

    // MARK: - Poll

    private func poll(transactionID: String) async -> FlowOutcome {
        state.isPolling = true
        // The deadline is measured from the start of polling, so the retry-after loop does not use up the budget.
        let start = await scheduler.elapsed()

        while await scheduler.elapsed() - start < FlowLimits.pollDeadline {
            if Task.isCancelled { return await stopped() }

            do {
                let status = try await client.status(transactionID: transactionID)
                let effects = PaymentFlowReducer.reduce(
                    state: &state,
                    event: .statusReceived(status),
                    messages: messages
                )
                if let outcome = await apply(effects) {
                    return outcome
                }
            } catch {
                // Transient, so polling continues until the deadline.
            }

            // A cancelled sleep returns at once, so the error must not be swallowed.
            do {
                try await scheduler.sleep(for: FlowLimits.pollInterval)
            } catch {
                return await stopped()
            }
        }

        let effects = PaymentFlowReducer.reduce(
            state: &state, event: .pollDeadlineReached, messages: messages
        )
        return await apply(effects)
            ?? .finished(.pending(transactionID: transactionID, reason: .pollTimeout))
    }

    private func stopped() async -> FlowOutcome {
        state.isPolling = false
        presentationTask?.cancel()
        presentationTask = nil
        await presenter.dismiss()
        return .finished(.cancelled(transactionID: state.transactionID))
    }

    // Both outcomes are handled alike: the server owns the verdict, and polling surfaces it.
    private func threeDSResolved(_ outcome: ThreeDSOutcome) async {
        let effects = PaymentFlowReducer.reduce(
            state: &state, event: .threeDSCompleted, messages: messages
        )
        _ = await apply(effects)
    }

    /// Runs the reducer's effects and returns an outcome when the run is over.
    private func apply(_ effects: [PaymentFlowEffect]) async -> FlowOutcome? {
        var outcome: FlowOutcome?

        for effect in effects {
            switch effect {
            case .dismiss3DS:
                await presenter.dismiss()

            case .present3DS(let step):
                // Not awaited: polling continues while the challenge is shown, as on Android.
                presentationTask?.cancel()
                presentationTask = Task { [presenter] in
                    let outcome = await presenter.present(step)
                    // A cancelled step must not dismiss the step that replaced it.
                    guard !Task.isCancelled else { return }
                    await self.threeDSResolved(outcome)
                }

            case .finish(let result):
                presentationTask?.cancel()
                presentationTask = nil
                outcome = .finished(result)

            case .stopPolling:
                state.isPolling = false
                if outcome == nil {
                    outcome = .reArmForm(message: state.inlineError ?? messages.paymentFailed)
                }
            }
        }

        // A finish wins over a re-arm in the same batch.
        if case .some(.reArmForm) = outcome, state.result != nil {
            return .finished(state.result!)
        }
        return outcome
    }
}
