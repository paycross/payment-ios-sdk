#if os(iOS)
import Foundation
import PayCrossCore

/// Entry point for the PayCross SDK.
///
/// ```swift
/// PayCrossAPI.configure(environment: .sandbox)
/// let sheet = PaymentSheet(sessionToken: token)
/// let result = await sheet.present(from: viewController)
/// ```
public enum PayCrossAPI {

    /// The SDK version, stamped into the User-Agent.
    public static let version = "0.5.0"

    private static let state = ConfigurationBox()

    /// Configures the SDK. Call once, before presenting a payment sheet.
    public static func configure(
        environment: PayCrossEnvironment,
        testCardPrefill: TestCardPrefill? = nil,
        applePayMerchantIdentifier: String? = nil
    ) {
        state.set(Configuration(
            environment: environment,
            testCardPrefill: testCardPrefill,
            applePayMerchantIdentifier: applePayMerchantIdentifier
        ))
    }

    static var configuration: Configuration? {
        state.get()
    }
}

/// Resolved SDK configuration.
public struct Configuration: Sendable {
    public let environment: PayCrossEnvironment
    public let testCardPrefill: TestCardPrefill?

    /// The merchant's own Apple merchant identifier, e.g. `merchant.example.com`.
    ///
    /// Nil means no Apple Pay button, ever, and that is the correct default:
    /// Apple's key derivation hashes this string into every payment token's
    /// key, so a payment made without it cannot be decrypted by anybody. The
    /// same string has to appear in three places -- here, in the app's Apple Pay
    /// entitlement, and on the merchant record in the PayCross back office --
    /// and the edge refuses a payment where the first and the last disagree.
    public let applePayMerchantIdentifier: String?

    /// Prefill is ignored in production, matching `effectiveTestPrefill()` on Android.
    public var effectiveTestCardPrefill: TestCardPrefill? {
        environment.allowsTestCardPrefill ? testCardPrefill : nil
    }
}

/// Prefills the card form for manual test runs. Ignored in production.
///
/// Deliberately not `Codable`: it carries a PAN and a CVV, and a synthesised
/// encoder is an invitation to persist them.
public struct TestCardPrefill: Sendable {
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
}

extension TestCardPrefill: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let tail = pan.count >= 4 ? String(pan.suffix(4)) : ""
        return "TestCardPrefill(pan: ****\(tail), cvv: •••)"
    }

    public var debugDescription: String { description }
}

/// Holds configuration across threads without requiring an actor hop at read time.
private final class ConfigurationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Configuration?

    func set(_ new: Configuration) {
        lock.lock()
        defer { lock.unlock() }
        value = new
    }

    func get() -> Configuration? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
#endif
