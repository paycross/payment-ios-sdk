import Foundation

/// What to do once the session has been fetched.
package enum SessionResolution: Sendable, Equatable {
    /// Show the card form. The session is open and there is nothing in flight.
    case showForm(SessionData?)
    /// A transaction already exists — poll it rather than creating another.
    case resume(transactionID: String)
    /// The session is already over; deliver this without showing a form.
    case finish(PaymentResult)
}

/// Decides whether a fetched session should show a form, resume, or finish.
///
/// A pure function in Core rather than a branch inside the sheet, because the
/// consequence of getting it wrong is a **second authorization against a session
/// that has already been paid**: without this, a `completed` session renders the
/// form, the shopper pays again, and the fresh idempotency key gives the backend
/// no signal that the two submissions are related.
///
/// Mirrors `PaymentViewModel.initialize` (`PaymentViewModel.kt:135-155`).
package enum SessionResolver {

    /// - Parameters:
    ///   - response: the fetched session, or nil when the fetch failed.
    ///   - claims: decoded from the session token, used for the amount when the
    ///     session completed without naming a transaction.
    ///   - localTransactionID: a transaction this client already started, which
    ///     takes precedence over the server's `latest_transaction_id`.
    package static func resolve(
        _ response: SessionResponse?,
        claims: SessionClaims,
        localTransactionID: String? = nil
    ) -> SessionResolution {
        let resumeID = localTransactionID ?? response?.latestTransactionID.nonEmpty

        switch response?.status {
        case SessionLifecycle.expired:
            // Fail before the shopper types a card, not after.
            return .finish(.failed(transactionID: resumeID, recovery: .restart))

        case SessionLifecycle.completed:
            guard let resumeID else {
                // Paid, with no transaction reference to report. This is the
                // edge case PaymentResult.succeeded's documentation describes.
                return .finish(.succeeded(
                    transactionID: "",
                    status: "success",
                    amount: claims.amount
                ))
            }
            return .resume(transactionID: resumeID)

        default:
            // Open, unknown, or the fetch failed. A transaction already in flight
            // is resumed; otherwise the shopper enters a card.
            if let resumeID { return .resume(transactionID: resumeID) }
            return .showForm(response?.data)
        }
    }
}

private extension Optional where Wrapped == String {
    /// Treats "" as absent — an empty `latest_transaction_id` is not a
    /// transaction to resume.
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return self
    }
}
