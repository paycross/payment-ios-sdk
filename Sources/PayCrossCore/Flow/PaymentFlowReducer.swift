import Foundation

/// Timing and retry limits, taken from `PaymentViewModel.kt`.
///
/// Read from the Kotlin, not from the docs: `docs/DESIGN.md` still describes an
/// abandoned exponential backoff (1s→5s over 60 attempts) and `docs/API.md` says
/// "every 3 seconds". Neither matches what ships.
package enum FlowLimits {
    /// `MAX_SUBMIT_ATTEMPTS` — retry-after loop cap.
    package static let maxSubmitAttempts = 5
    /// `POLL_INTERVAL_MS`
    package static let pollInterval: Duration = .milliseconds(2000)
    /// `POLL_DEADLINE_MS` — 8 minutes.
    package static let pollDeadline: Duration = .seconds(480)
}

/// What the flow is doing right now.
package struct PaymentFlowState: Sendable, Equatable {
    package var transactionID: String?
    package var isPolling: Bool = false
    /// Inline error shown on the re-armed form after a retryable decline.
    package var inlineError: String?
    /// The 3DS step currently being presented, if any.
    package var pendingThreeDS: ThreeDSStep?
    /// Dedupe keys for 3DS actions already presented in this session.
    package var handledThreeDSKeys: Set<String> = []
    package var result: PaymentResult?
    /// Claims are the fallback for amount/currency when the status response omits them.
    package var claims: SessionClaims?

    package init(claims: SessionClaims? = nil) {
        self.claims = claims
    }
}

package struct ThreeDSStep: Sendable, Equatable {
    package let action: ThreeDSAction
    package let isChallenge: Bool
}

/// Things that happen to the flow.
package enum PaymentFlowEvent: Sendable, Equatable {
    case statusReceived(StatusResponse)
    case threeDSCompleted
    case pollDeadlineReached
}

/// What the runner should do next.
///
/// `stopPolling` is separate from `finish` on purpose: a *retryable* decline stops
/// the poll loop without producing a result, because Android's `handleStatus`
/// returns `true` (terminal for the loop) while only setting an inline error.
/// Collapsing these two would leave a dead transaction being polled for 8 minutes.
package enum PaymentFlowEffect: Sendable, Equatable {
    case stopPolling
    case present3DS(ThreeDSStep)
    case dismiss3DS
    case finish(PaymentResult)
}

/// The payment flow as a pure function.
///
/// Everything the Kotlin `PaymentViewModel` does in response to a status response
/// lives here, synchronously and without a network or a UI, so it is asserted in
/// microseconds on Linux.
package enum PaymentFlowReducer {

    package static func reduce(
        state: inout PaymentFlowState,
        event: PaymentFlowEvent
    ) -> [PaymentFlowEffect] {
        switch event {
        case .threeDSCompleted:
            // The action stays in the handled set, so polling won't re-show it.
            state.pendingThreeDS = nil
            return []

        case .pollDeadlineReached:
            state.isPolling = false
            let result = PaymentResult.failed(transactionID: state.transactionID, recovery: .retry)
            state.result = result
            return [.stopPolling, .finish(result)]

        case .statusReceived(let status):
            return apply(status: status, to: &state)
        }
    }

    private static func apply(
        status: StatusResponse,
        to state: inout PaymentFlowState
    ) -> [PaymentFlowEffect] {
        switch TransactionStatus(rawValue: status.status) {
        case .success, .authorized:
            state.isPolling = false
            state.pendingThreeDS = nil
            // Android coalesces amount and currency INDEPENDENTLY, so a status
            // carrying only one of them still picks up the other from claims.
            let amount = Amount(
                minorUnits: status.amount ?? state.claims?.amount.minorUnits ?? 0,
                currencyCode: status.currency ?? state.claims?.amount.currencyCode ?? ""
            )
            let result = PaymentResult.succeeded(
                transactionID: status.transactionID,
                status: status.status,
                amount: amount
            )
            state.result = result
            return [.stopPolling, .dismiss3DS, .finish(result)]

        case .failed:
            let recovery = Recovery(apiValue: status.recovery)
            state.isPolling = false
            state.pendingThreeDS = nil

            if recovery.isRetryable {
                // Re-arm the form like the checkout page does. No result is
                // produced, but the poll loop still stops.
                state.transactionID = nil
                state.handledThreeDSKeys.removeAll()
                state.inlineError = "Payment failed. Please try again."
                return [.stopPolling, .dismiss3DS]
            }

            let result = PaymentResult.failed(
                transactionID: status.transactionID,
                recovery: recovery
            )
            state.result = result
            return [.stopPolling, .dismiss3DS, .finish(result)]

        case .threeDSFingerprint, .threeDSChallenge:
            guard let action = status.action else { return [] }
            let key = dedupeKey(status: status.status, action: action)
            guard state.handledThreeDSKeys.insert(key).inserted else { return [] }
            let step = ThreeDSStep(
                action: action,
                isChallenge: status.status == TransactionStatus.threeDSChallenge.rawValue
            )
            state.pendingThreeDS = step
            return [.present3DS(step)]

        case nil:
            // Unknown status: keep polling, exactly like Kotlin's `else -> false`.
            return []
        }
    }

    /// Stable dedupe key for a 3DS action.
    ///
    /// Android builds `"${status}|${url}|${data}"`, where `data` is a Gson-backed
    /// `LinkedHashMap` whose `toString()` is insertion-ordered. Swift `Dictionary`
    /// has no stable order, so interpolating it directly would produce a different
    /// key for the same action and re-present the challenge mid-payment. Sorting
    /// the pairs makes the key deterministic.
    static func dedupeKey(status: String, action: ThreeDSAction) -> String {
        let data = action.data.map { dict in
            "{" + dict.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ") + "}"
        } ?? "null"
        return "\(status)|\(action.url)|\(data)"
    }
}
