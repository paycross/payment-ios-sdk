import Foundation

public enum DemoDeepLink: Sendable, Equatable {
    case run(merchant: String, scenario: String, surface: CheckoutSurface)
    case result

    public static let scheme = "paycross-demo"

    public static func parse(_ url: URL) -> DemoDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        switch url.host?.lowercased() {
        case "result":
            return .result
        case "run":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in
                items.first { $0.name == name }?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let merchant = value("merchant"), !merchant.isEmpty,
                  let scenario = value("scenario"), !scenario.isEmpty else {
                return nil
            }
            let surface = value("surface").flatMap { CheckoutSurface(rawValue: $0.lowercased()) } ?? .sdk
            return .run(merchant: merchant, scenario: scenario, surface: surface)
        default:
            return nil
        }
    }
}

public enum BodyTemplate {
    public static let returnDeepLink = "\(DemoDeepLink.scheme)://result"

    public static func substitute(
        _ body: String,
        timestamp: Int64,
        uuid: String
    ) -> String {
        body
            .replacingOccurrences(of: "{{timestamp}}", with: String(timestamp))
            .replacingOccurrences(of: "{{uuid}}", with: uuid)
    }

    public static func withDeepLinkReturn(_ body: String) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: Data(body.utf8))
            as? [String: Any] else {
            throw HarnessError.invalidBody("request body is not a JSON object")
        }
        object["return_url"] = "\(returnDeepLink)?nav=return"
        object["success_url"] = "\(returnDeepLink)?nav=success"

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }
}

public enum HarnessError: Error, Sendable, Equatable {
    case invalidBody(String)
    case tokenRequestFailed(Int)
    case sessionRequestFailed(Int, String?)
    case missingField(String)
}

public enum SessionOutcome {
    public enum Phase: String, Sendable, Equatable {
        case success
        case failed
        case pending
    }

    public struct Resolution: Sendable, Equatable {
        public let phase: Phase
        public let detail: String
        public let transactionID: String?
        public let amount: Int64?
        public let currency: String?
    }

    public static let terminalStatuses: Set<String> = ["completed", "failed", "expired", "cancelled"]
    public static let paidStatuses: Set<String> = ["succeeded", "captured", "authorized"]

    public static func resolve(session: [String: Any]) -> Resolution {
        let status = (session["status"] as? String) ?? ""

        guard terminalStatuses.contains(status) else {
            return Resolution(
                phase: .pending, detail: status, transactionID: nil,
                amount: nil, currency: nil
            )
        }

        guard status == "completed" else {
            return Resolution(
                phase: .failed, detail: "Session \(status)", transactionID: nil,
                amount: nil, currency: nil
            )
        }

        guard let payment = primaryPaymentTransaction(session) else {
            return Resolution(
                phase: .failed, detail: "Completed with no payment transaction",
                transactionID: nil, amount: nil, currency: nil
            )
        }

        let paymentStatus = (payment["status"] as? String) ?? ""
        let amount = (payment["amount"] as? NSNumber)?.int64Value
        let currency = payment["currency"] as? String

        return Resolution(
            phase: paidStatuses.contains(paymentStatus) ? .success : .failed,
            detail: "\(paymentStatus) · \(amount.map(String.init) ?? "-") \(currency ?? "")",
            transactionID: payment["id"] as? String,
            amount: amount,
            currency: currency
        )
    }

    static func primaryPaymentTransaction(_ session: [String: Any]) -> [String: Any]? {
        guard let transactions = session["transactions"] as? [Any] else { return nil }

        var latest: [String: Any]?
        for case let txn as [String: Any] in transactions {
            guard (txn["type"] as? String) == "payment" else { continue }
            if let parent = txn["parent_transaction_id"] as? String, !parent.isEmpty { continue }
            if latest == nil || sortKey(txn) >= sortKey(latest!) {
                latest = txn
            }
        }
        return latest
    }

    static func sortKey(_ txn: [String: Any]) -> String {
        let updated = (txn["updated_at"] as? String) ?? ""
        if !updated.isEmpty { return updated }
        return (txn["created_at"] as? String) ?? ""
    }
}
