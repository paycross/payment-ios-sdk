import Foundation

/// A 3DS step the server is asking the client to perform.
///
/// Declared here once and referenced everywhere else — the design had this type
/// specified in two sections with different members.
package struct ThreeDSAction: Codable, Sendable, Hashable {
    package let url: String
    package let method: String
    package let data: [String: String]?

    package init(url: String, method: String, data: [String: String]? = nil) {
        self.url = url
        self.method = method
        self.data = data
    }

    /// True when the action must be submitted as a form POST rather than a GET.
    package var isPost: Bool {
        method.uppercased() == "POST"
    }
}

package struct StatusResponse: Codable, Sendable, Hashable {
    package let transactionID: String
    package let status: String
    package let amount: Int64?
    package let currency: String?
    package let action: ThreeDSAction?
    package let recovery: String?
    /// The token for a card this payment stored, on a terminal status only.
    ///
    /// The wire also carries `used_token`, naming the stored card this payment
    /// was taken from. It is deliberately not decoded: the sheet picked that
    /// card, so the merchant already knows it, and the only new fact here is
    /// the token that did not exist before this payment.
    package let savedToken: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case savedToken = "saved_token"
        case status, amount, currency, action, recovery
    }

    package init(
        transactionID: String,
        status: String,
        amount: Int64? = nil,
        currency: String? = nil,
        action: ThreeDSAction? = nil,
        recovery: String? = nil,
        savedToken: String? = nil
    ) {
        self.transactionID = transactionID
        self.status = status
        self.amount = amount
        self.currency = currency
        self.action = action
        self.recovery = recovery
        self.savedToken = savedToken
    }
}

package struct SubmitCardResponse: Codable, Sendable, Hashable {
    package let success: Bool?
    package let transactionID: String?
    package let cached: Bool?
    package let error: String?
    package let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case retryAfter = "retry_after"
        case success, cached, error
    }

    package init(
        success: Bool? = nil,
        transactionID: String? = nil,
        cached: Bool? = nil,
        error: String? = nil,
        retryAfter: Int? = nil
    ) {
        self.success = success
        self.transactionID = transactionID
        self.cached = cached
        self.error = error
        self.retryAfter = retryAfter
    }
}

/// The transaction statuses the flow reacts to.
///
/// Anything not listed here is ignored and polling continues, matching the
/// Kotlin `else -> return false`.
package enum TransactionStatus: String, Sendable {
    case success
    case authorized
    case failed
    case threeDSFingerprint = "threeds_fingerprint"
    case threeDSChallenge = "threeds_challenge"
}
