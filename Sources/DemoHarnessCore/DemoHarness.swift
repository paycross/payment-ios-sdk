import Foundation

/// The automation contract.
///
/// On Android an adb runner drives the harness with
/// `paycross-demo://run?merchant=&scenario=&surface=`, and the app answers on a
/// logcat tag. The URL half ports directly; the log half does not, so the iOS
/// equivalent writes to the unified log instead (see `HarnessLog`).
public enum DemoDeepLink: Sendable, Equatable {
    /// Start a scenario. Names, not ids, so a runner can be written against the
    /// seed data without first reading the device's storage.
    case run(merchant: String, scenario: String, surface: CheckoutSurface)
    /// The hosted checkout bounced back to the app.
    case result

    public static let scheme = "paycross-demo"

    public static func parse(_ url: URL) -> DemoDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // A custom-scheme URL puts the first path element in `host`.
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
            // An unrecognised surface falls back to the SDK sheet rather than
            // failing the run, matching the Kotlin's `?: "sdk"`.
            let surface = value("surface").flatMap { CheckoutSurface(rawValue: $0.lowercased()) } ?? .sdk
            return .run(merchant: merchant, scenario: scenario, surface: surface)
        default:
            return nil
        }
    }
}

/// Fills the placeholders a scenario body may contain.
public enum BodyTemplate {

    public static let returnDeepLink = "\(DemoDeepLink.scheme)://result"

    /// Substitutes `{{timestamp}}` and `{{uuid}}`.
    ///
    /// Both are injected rather than read from the environment so a test can
    /// assert the output exactly.
    public static func substitute(
        _ body: String,
        timestamp: Int64,
        uuid: String
    ) -> String {
        body
            .replacingOccurrences(of: "{{timestamp}}", with: String(timestamp))
            .replacingOccurrences(of: "{{uuid}}", with: uuid)
    }

    /// Points the session's return and success URLs back at the app, so a hosted
    /// checkout in a browser can bounce the tester home when it finishes.
    public static func withDeepLinkReturn(_ body: String) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: Data(body.utf8))
            as? [String: Any] else {
            throw HarnessError.invalidBody("request body is not a JSON object")
        }
        object["return_url"] = "\(returnDeepLink)?nav=return"
        object["success_url"] = "\(returnDeepLink)?nav=success"

        // withoutEscapingSlashes matters here: the default escapes "/" as "\/",
        // so the deep link would render as paycross-demo:\/\/result. That is valid
        // JSON, but this body is shown to the tester and pasted into curl, where
        // the escaping is confusing noise.
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

/// Reads an outcome out of a fetched session.
///
/// Mirrors `getPrimaryPaymentTransaction` in payx-tkg, which the Android harness
/// also mirrors — the three implementations must agree or the same run reports
/// differently depending on where it was observed.
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

    /// Terminal session statuses. Anything else means keep polling.
    public static let terminalStatuses: Set<String> = ["completed", "failed", "expired", "cancelled"]
    /// Payment statuses that count as money taken.
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

    /// The latest parentless `payment` transaction.
    static func primaryPaymentTransaction(_ session: [String: Any]) -> [String: Any]? {
        guard let transactions = session["transactions"] as? [[String: Any]] else { return nil }

        var latest: [String: Any]?
        for txn in transactions {
            guard (txn["type"] as? String) == "payment" else { continue }
            // A transaction with a parent is a refund/capture of another one.
            if let parent = txn["parent_transaction_id"] as? String, !parent.isEmpty { continue }
            if latest == nil || sortKey(txn) >= sortKey(latest!) {
                latest = txn
            }
        }
        return latest
    }

    /// `updated_at`, falling back to `created_at`.
    ///
    /// Read through an explicit nil check: a JSON null must become "" and sort
    /// below every ISO timestamp, not above it.
    static func sortKey(_ txn: [String: Any]) -> String {
        let updated = (txn["updated_at"] as? String) ?? ""
        if !updated.isEmpty { return updated }
        return (txn["created_at"] as? String) ?? ""
    }
}
