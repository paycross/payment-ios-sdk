import Foundation

package enum SessionResolution: Sendable, Equatable {
    case showForm(SessionData?)
    case resume(transactionID: String)
    case finish(PaymentResult)
}

/// Decides whether a fetched session shows a form, resumes a transaction, or finishes. A completed session never shows a form again.
package enum SessionResolver {

    package static func resolve(
        _ response: SessionResponse?,
        claims: SessionClaims,
        localTransactionID: String? = nil
    ) -> SessionResolution {
        let resumeID = localTransactionID ?? response?.latestTransactionID.nonEmpty

        switch response?.status {
        case SessionLifecycle.expired:
            return .finish(.failed(transactionID: resumeID, recovery: .restart))

        case SessionLifecycle.completed:
            guard let resumeID else {
                return .finish(.succeeded(
                    transactionID: "",
                    status: "success",
                    amount: claims.amount,
                    savedCardToken: nil
                ))
            }
            return .resume(transactionID: resumeID)

        default:
            if let resumeID { return .resume(transactionID: resumeID) }
            return .showForm(response?.data)
        }
    }
}

private extension Optional where Wrapped == String {
    /// Returns nil for an empty string.
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return self
    }
}
