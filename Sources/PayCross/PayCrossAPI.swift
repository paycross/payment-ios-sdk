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
    public static let version = "0.7.0"

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

    /// The merchant's own Apple merchant identifier, e.g. `merchant.example.com`.
    ///
    /// Nil means no Apple Pay button, ever, and that is the correct default:
    /// Apple's key derivation hashes this string into every payment token's
    /// key, so a payment made without it cannot be decrypted by anybody. The
    /// same string has to appear in three places -- here, in the app's Apple Pay
    /// entitlement, and on the merchant record in the PayCross back office --
    /// and the edge refuses a payment where the first and the last disagree.
    public let applePayMerchantIdentifier: String?

    /// How the sheet should look.
    ///
    /// Nil is not "no theming": the sheet still picks up the brand colour the
    /// merchant set in the back office, which arrives with the session. Every
    /// role a merchant leaves unset keeps the platform colour the sheet already
    /// draws, so an appearance that names one colour changes one colour.
    public let appearance: PayCrossAppearance?

    /// The language the sheet should speak, as a BCP-47 tag such as `fr` or
    /// `fr-CA`.
    ///
    /// Nil means the sheet decides: the session's own `locale` if the server
    /// sent one, else the shopper's device, else English. Set it only when the
    /// merchant's app has already asked the shopper what language they read in
    /// and wants the sheet to agree.
    ///
    /// A tag the SDK ships no strings for is passed over rather than ending the
    /// search, so asking for a language the sheet does not speak leaves the
    /// session and the device their turn at it. The amount is a separate answer
    /// and is not clamped to what the SDK ships: see `LOCALIZATION.md`.
    public let locale: String?

    /// Defaulted rather than left to the synthesised memberwise initialiser, so
    /// that adding a field here does not break every call site that never had
    /// an opinion about it.
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
