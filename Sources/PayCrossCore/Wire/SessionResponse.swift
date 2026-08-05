import Foundation

/// `GET session/{id}` — the session's status and its latest transaction.
public struct SessionResponse: Codable, Sendable, Hashable {
    public let id: String
    public let status: String
    public let amount: Int64?
    public let currency: String?
    public let transaction: SessionTransaction?

    public init(
        id: String,
        status: String,
        amount: Int64? = nil,
        currency: String? = nil,
        transaction: SessionTransaction? = nil
    ) {
        self.id = id
        self.status = status
        self.amount = amount
        self.currency = currency
        self.transaction = transaction
    }

    /// Whether the session has reached a state that will not change again.
    public var isTerminal: Bool {
        SessionStatus.terminal.contains(status)
    }
}

public struct SessionTransaction: Codable, Sendable, Hashable {
    public let id: String
    public let status: String

    public init(id: String, status: String) {
        self.id = id
        self.status = status
    }
}

public enum SessionStatus {
    /// Session statuses after which nothing further happens.
    public static let terminal: Set<String> = ["completed", "failed", "expired", "cancelled"]
    /// Payment statuses that count as money captured.
    public static let paid: Set<String> = ["succeeded", "captured", "authorized"]
}
