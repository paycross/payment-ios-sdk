import Foundation

/// A merchant the harness can mint sessions against.
public struct Merchant: Codable, Sendable, Hashable, Identifiable {
    public enum Environment: String, Codable, Sendable {
        case staging = "STAGING"
        case production = "PRODUCTION"
    }

    public var id: String
    public var name: String
    public var environment: Environment
    public var tokenURL: String
    public var clientID: String
    public var clientSecret: String
    public var paymentAPIURL: String
    public var paycrossVersion: String

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        environment: Environment = .staging,
        tokenURL: String = "",
        clientID: String = "",
        clientSecret: String = "",
        paymentAPIURL: String = "",
        paycrossVersion: String = ""
    ) {
        self.id = id
        self.name = name
        self.environment = environment
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.paymentAPIURL = paymentAPIURL
        self.paycrossVersion = paycrossVersion
    }

    public var isProduction: Bool { environment == .production }

    /// Older harness configs wrote `payment_sessions`; the API path is hyphenated.
    public var sessionsURL: String {
        paymentAPIURL.replacingOccurrences(of: "payment_sessions", with: "payment-sessions")
    }
}

public struct CardPrefill: Codable, Sendable, Hashable {
    public var cardholderName: String
    public var pan: String
    public var expireMonth: String
    public var expireYear: String
    public var cvv: String
    public var saveCard: Bool

    public init(
        cardholderName: String = "",
        pan: String = "",
        expireMonth: String = "",
        expireYear: String = "",
        cvv: String = "",
        saveCard: Bool = false
    ) {
        self.cardholderName = cardholderName
        self.pan = pan
        self.expireMonth = expireMonth
        self.expireYear = expireYear
        self.cvv = cvv
        self.saveCard = saveCard
    }

    /// Nil when there is no card to prefill, matching `toTestCardPrefillOrNull`.
    public var isUsable: Bool {
        !pan.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public struct Scenario: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var merchantID: String
    public var name: String
    public var card: CardPrefill
    public var requestBody: String
    public var hint: String?

    public init(
        id: String = UUID().uuidString,
        merchantID: String,
        name: String,
        card: CardPrefill = CardPrefill(),
        requestBody: String,
        hint: String? = nil
    ) {
        self.id = id
        self.merchantID = merchantID
        self.name = name
        self.card = card
        self.requestBody = requestBody
        self.hint = hint
    }
}

/// Which surface a session was opened on.
public enum CheckoutSurface: String, Codable, Sendable, CaseIterable {
    /// The native SDK sheet.
    case sdk
    /// The hosted checkout page in a browser.
    case browser
    /// A copied link, opened wherever.
    case link
    /// A QR code, scanned on another device.
    case qr

    /// Whether outcomes for this surface must be discovered by polling the
    /// session rather than from an SDK callback.
    public var requiresPolling: Bool { self != .sdk }
}

/// One minted session on any surface.
public struct RunRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var merchantID: String
    public var scenarioName: String
    public var surface: CheckoutSurface
    public var sessionID: String
    public var sessionURL: String
    public var checkoutURL: String
    public var requestBody: String
    public var outcome: String
    public var transactionID: String?
    public var amount: Int64?
    public var currency: String?

    public static let pendingOutcome = "pending"

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        merchantID: String = "",
        scenarioName: String = "",
        surface: CheckoutSurface = .sdk,
        sessionID: String = "",
        sessionURL: String = "",
        checkoutURL: String = "",
        requestBody: String = "",
        outcome: String = RunRecord.pendingOutcome,
        transactionID: String? = nil,
        amount: Int64? = nil,
        currency: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.merchantID = merchantID
        self.scenarioName = scenarioName
        self.surface = surface
        self.sessionID = sessionID
        self.sessionURL = sessionURL
        self.checkoutURL = checkoutURL
        self.requestBody = requestBody
        self.outcome = outcome
        self.transactionID = transactionID
        self.amount = amount
        self.currency = currency
    }

    public var isPending: Bool { outcome == RunRecord.pendingOutcome }
}

public struct DemoData: Codable, Sendable {
    public var merchants: [Merchant]
    public var scenarios: [Scenario]
    public var selectedMerchantID: String?
    public var runs: [RunRecord]

    /// Bounded so the harness cannot grow without limit on a test device.
    public static let maxRuns = 50

    public init(
        merchants: [Merchant] = [],
        scenarios: [Scenario] = [],
        selectedMerchantID: String? = nil,
        runs: [RunRecord] = []
    ) {
        self.merchants = merchants
        self.scenarios = scenarios
        self.selectedMerchantID = selectedMerchantID
        self.runs = runs
    }

    public mutating func record(_ run: RunRecord) {
        runs.insert(run, at: 0)
        if runs.count > Self.maxRuns {
            runs = Array(runs.prefix(Self.maxRuns))
        }
    }

    public func scenarios(for merchantID: String) -> [Scenario] {
        scenarios.filter { $0.merchantID == merchantID }
    }
}
