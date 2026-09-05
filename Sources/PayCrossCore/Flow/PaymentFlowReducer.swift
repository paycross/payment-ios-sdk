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

    /// - Parameter now: the reference date, for the session-expiry check. Taken as
    ///   a parameter rather than read from the clock so the boundary is testable.
    package static func reduce(
        state: inout PaymentFlowState,
        event: PaymentFlowEvent,
        now: Date = Date()
    ) -> [PaymentFlowEffect] {
        switch event {
        case .threeDSCompleted:
            // The action stays in the handled set, so polling won't re-show it.
            state.pendingThreeDS = nil
            // Emitting the dismissal is what actually removes the web view.
            // Returning [] here left an answered challenge full-screen over the
            // form until the next poll returned terminal, and left a completed
            // fingerprint's web view in the hierarchy for the life of the sheet.
            return [.dismiss3DS]

        case .pollDeadlineReached:
            state.isPolling = false
            // The poll ran out without ever seeing an outcome, and a full network
            // loss is indistinguishable from a blip the loop was right to ignore.
            // The payment may have succeeded and shifted liability, so this is not
            // a failure at all: the transaction id is here to resolve it out of band.
            let result = PaymentResult.pending(
                transactionID: state.transactionID,
                reason: .pollTimeout
            )
            state.result = result
            return [.stopPolling, .finish(result)]

        case .statusReceived(let status):
            return apply(status: status, to: &state, now: now)
        }
    }

    private static func apply(
        status: StatusResponse,
        to state: inout PaymentFlowState,
        now: Date
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
                // Only while the session can still take a payment. Nothing else
                // bounds a re-armed form — the 480s poll deadline goes with the
                // poll — so the sheet would sit on a live Pay button long after
                // the session expired, and the next tap could only fail.
                if state.claims?.isExpired(now: now) == true {
                    let result = SessionLifetime.expired
                    state.result = result
                    return [.stopPolling, .dismiss3DS, .finish(result)]
                }

                // Re-arm the form like the checkout page does. No result is
                // produced, but the poll loop still stops.
                state.transactionID = nil
                state.handledThreeDSKeys.removeAll()
                state.inlineError = "Payment failed. Please try again."
                return [.stopPolling, .dismiss3DS]
            }

            if case .verifyBeforeRetry = recovery {
                // The server has no verdict either, so this is the same unknown
                // outcome the poll deadline produces and must reach the merchant
                // the same way. Delivered as a decline it reads as "collect again".
                let result = PaymentResult.pending(
                    transactionID: status.transactionID,
                    reason: .serverVerify
                )
                state.result = result
                return [.stopPolling, .dismiss3DS, .finish(result)]
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
