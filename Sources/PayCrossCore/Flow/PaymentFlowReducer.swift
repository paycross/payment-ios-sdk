import Foundation

package enum FlowLimits {
    package static let maxSubmitAttempts = 5
    package static let pollInterval: Duration = .milliseconds(2000)
    package static let pollDeadline: Duration = .seconds(480)
}

package struct PaymentFlowState: Sendable, Equatable {
    package var transactionID: String?
    package var isPolling: Bool = false
    package var inlineError: String?
    package var pendingThreeDS: ThreeDSStep?
    package var handledThreeDSKeys: Set<String> = []
    package var result: PaymentResult?
    package var claims: SessionClaims?

    package init(claims: SessionClaims? = nil) {
        self.claims = claims
    }
}

package struct ThreeDSStep: Sendable, Equatable {
    package let action: ThreeDSAction
    package let isChallenge: Bool
}

package enum PaymentFlowEvent: Sendable, Equatable {
    case statusReceived(StatusResponse)
    case threeDSCompleted
    case pollDeadlineReached
}

/// What the runner should do next. `stopPolling` is separate from `finish`: a retryable decline stops polling without a result.
package enum PaymentFlowEffect: Sendable, Equatable {
    case stopPolling
    case present3DS(ThreeDSStep)
    case dismiss3DS
    case finish(PaymentResult)
}

package enum PaymentFlowReducer {

    package static func reduce(
        state: inout PaymentFlowState,
        event: PaymentFlowEvent,
        now: Date = Date(),
        messages: FlowMessages = .english
    ) -> [PaymentFlowEffect] {
        switch event {
        case .threeDSCompleted:
            state.pendingThreeDS = nil
            // Returning nothing here would leave the web view on screen.
            return [.dismiss3DS]

        case .pollDeadlineReached:
            state.isPolling = false
            // A network loss looks like a blip, so the outcome is unknown rather than failed.
            let result = PaymentResult.pending(
                transactionID: state.transactionID,
                reason: .pollTimeout
            )
            state.result = result
            return [.stopPolling, .finish(result)]

        case .statusReceived(let status):
            return apply(status: status, to: &state, now: now, messages: messages)
        }
    }

    private static func apply(
        status: StatusResponse,
        to state: inout PaymentFlowState,
        now: Date,
        messages: FlowMessages
    ) -> [PaymentFlowEffect] {
        switch TransactionStatus(rawValue: status.status) {
        case .success, .authorized:
            state.isPolling = false
            state.pendingThreeDS = nil
            // Amount and currency fall back to the claims independently, as on Android.
            let amount = Amount(
                minorUnits: status.amount ?? state.claims?.amount.minorUnits ?? 0,
                currencyCode: status.currency ?? state.claims?.amount.currencyCode ?? ""
            )
            let result = PaymentResult.succeeded(
                transactionID: status.transactionID,
                status: status.status,
                amount: amount,
                savedCardToken: status.savedToken
            )
            state.result = result
            return [.stopPolling, .dismiss3DS, .finish(result)]

        case .failed:
            let recovery = Recovery(apiValue: status.recovery)
            state.isPolling = false
            state.pendingThreeDS = nil

            // Checked before the retryable branch: a verify-before-retry must never re-arm the form on a payment that may have succeeded.
            if case .verifyBeforeRetry = recovery {
                let result = PaymentResult.pending(
                    transactionID: status.transactionID,
                    reason: .serverVerify
                )
                state.result = result
                return [.stopPolling, .dismiss3DS, .finish(result)]
            }

            if recovery.isRetryable {
                // A re-armed form on an expired session could only fail on the next tap.
                if state.claims?.isExpired(now: now) == true {
                    let result = SessionLifetime.expired
                    state.result = result
                    return [.stopPolling, .dismiss3DS, .finish(result)]
                }

                state.transactionID = nil
                state.handledThreeDSKeys.removeAll()
                state.inlineError = messages.paymentFailed
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
            // Unknown statuses keep polling, as on Android.
            return []
        }
    }

    /// A dedupe key for a 3DS action. The data pairs are sorted because a Swift dictionary has no stable order.
    static func dedupeKey(status: String, action: ThreeDSAction) -> String {
        let data = action.data.map { dict in
            "{" + dict.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ") + "}"
        } ?? "null"
        return "\(status)|\(action.url)|\(data)"
    }
}
