import Foundation

/// The backend the SDK talks to.
public enum PayCrossEnvironment: Sendable, Hashable {
    case sandbox
    case production
    /// Sends requests to the given host. The host must use https, since card data is sent to it.
    case custom(baseURL: URL)

    package var baseURL: URL {
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

    /// Card prefill is disabled in production, matching the Android SDK.
    package var allowsTestCardPrefill: Bool {
        self != .production
    }

    package var isUsable: Bool {
        baseURL.scheme?.lowercased() == "https"
    }
}
