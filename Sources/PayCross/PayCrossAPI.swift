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
    public static let version = "0.8.0"

    private static let state = ConfigurationBox()

    /// Configures the SDK. Call once, before presenting a payment sheet.
    public static func configure(
        environment: PayCrossEnvironment,
        testCardPrefill: TestCardPrefill? = nil,
        applePayMerchantIdentifier: String? = nil,
        appearance: PayCrossAppearance? = nil,
        locale: String? = nil
    ) {
        state.set(Configuration(
            environment: environment,
            testCardPrefill: testCardPrefill,
            applePayMerchantIdentifier: applePayMerchantIdentifier,
            appearance: appearance,
            locale: locale
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

    /// The merchant's Apple merchant identifier, such as `merchant.example.com`.
    ///
    /// It must match the app's Apple Pay merchant ID entitlement. Nil hides the Apple Pay button.
    public let applePayMerchantIdentifier: String?

    /// How the sheet should look. Nil keeps the session's brand colour and the platform defaults.
    public let appearance: PayCrossAppearance?

    /// The language the sheet should speak, as a BCP-47 tag such as `fr` or `fr-CA`.
    ///
    /// Nil lets the sheet choose from the session, then the device, then English.
    public let locale: String?

    init(
        environment: PayCrossEnvironment,
        testCardPrefill: TestCardPrefill? = nil,
        applePayMerchantIdentifier: String? = nil,
        appearance: PayCrossAppearance? = nil,
        locale: String? = nil
    ) {
        self.environment = environment
        self.testCardPrefill = testCardPrefill
        self.applePayMerchantIdentifier = applePayMerchantIdentifier
        self.appearance = appearance
        self.locale = locale
    }

    /// The prefill when the environment allows one, otherwise nil.
    public var effectiveTestCardPrefill: TestCardPrefill? {
        environment.allowsTestCardPrefill ? testCardPrefill : nil
    }
}

// Not Codable, so the PAN and CVV cannot be persisted by accident.
/// Prefills the card form for manual test runs. Ignored in production.
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
