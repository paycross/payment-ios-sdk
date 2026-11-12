import Foundation

package struct ThreeDSAction: Codable, Sendable, Hashable {
    package let url: String
    package let method: String
    package let data: [String: String]?

    package init(url: String, method: String, data: [String: String]? = nil) {
        self.url = url
        self.method = method
        self.data = data
    }

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
    // used_token is not decoded: the sheet already picked that stored card.
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

// Unknown statuses keep polling, as on Android.
package enum TransactionStatus: String, Sendable {
    case success
    case authorized
    case failed
    case threeDSFingerprint = "threeds_fingerprint"
    case threeDSChallenge = "threeds_challenge"
}
