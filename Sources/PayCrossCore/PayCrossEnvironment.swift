import Foundation

/// The backend the SDK talks to.
public enum PayCrossEnvironment: Sendable, Hashable {
    case sandbox
    case production
    /// Points the SDK at an arbitrary host. Intended for local backend work.
    ///
    /// This case carries the PAN, the CVV and the session JWT to whatever host it
    /// names, so `isUsable` rejects anything that is not https.
    case custom(baseURL: URL)

    public var baseURL: URL {
        switch self {
        case .sandbox:
            // swiftlint:disable:next force_unwrapping
            URL(string: "https://checkout.test-pay-cross.com/api")!
        case .production:
            // swiftlint:disable:next force_unwrapping
            URL(string: "https://checkout.pay-cross.com/api")!
        case .custom(let url):
            url
        }
    }

    /// Card-form prefill is ignored in production, matching `effectiveTestPrefill()`
    /// in the Android SDK.
    public var allowsTestCardPrefill: Bool {
        self != .production
    }

    /// Rejects a `custom` environment that would send card data over cleartext.
    public var isUsable: Bool {
        baseURL.scheme?.lowercased() == "https"
    }
}
