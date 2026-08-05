import Foundation

/// A 3DS step the server is asking the client to perform.
///
/// Declared here once and referenced everywhere else — the design had this type
/// specified in two sections with different members.
public struct ThreeDSAction: Codable, Sendable, Hashable {
    public let url: String
    public let method: String
    public let data: [String: String]?

    public init(url: String, method: String, data: [String: String]? = nil) {
        self.url = url
        self.method = method
        self.data = data
    }

    /// True when the action must be submitted as a form POST rather than a GET.
    public var isPost: Bool {
        method.uppercased() == "POST"
    }
}

public struct StatusResponse: Codable, Sendable, Hashable {
    public let transactionID: String
    public let status: String
    public let amount: Int64?
    public let currency: String?
    public let action: ThreeDSAction?
    public let recovery: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case status, amount, currency, action, recovery
    }

    public init(
        transactionID: String,
        status: String,
        amount: Int64? = nil,
        currency: String? = nil,
        action: ThreeDSAction? = nil,
        recovery: String? = nil
    ) {
        self.transactionID = transactionID
        self.status = status
        self.amount = amount
        self.currency = currency
        self.action = action
        self.recovery = recovery
    }
}

public struct SubmitCardResponse: Codable, Sendable, Hashable {
    public let success: Bool?
    public let transactionID: String?
    public let cached: Bool?
    public let error: String?
    public let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case retryAfter = "retry_after"
        case success, cached, error
    }

    public init(
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
public enum TransactionStatus: String, Sendable {
    case success
    case authorized
    case failed
    case threeDSFingerprint = "threeds_fingerprint"
    case threeDSChallenge = "threeds_challenge"
}
