import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resolves the device's public IP for `browser_info.ip_address`.
///
/// The submit-card API rejects a blank value outright — `validateBrowserInfo` in
/// payment-submit-card returns "missing browser_info.ip_address" — and does not
/// derive it from the request. An earlier iOS design note claimed the backend
/// supplied it; that was false against both the Go and the Kotlin, and an SDK
/// that believes it submits nothing at all.
///
/// Mirrors `IpAddressProvider.kt`: one lookup, cached, with a loopback fallback
/// so a submission never blocks on a network that is already failing.
package actor IPAddressProvider {

    package static let fallback = "127.0.0.1"
    static let lookupURL = URL(string: "https://api.ipify.org?format=json")!

    private let transport: any HTTPTransport
    private let timeout: TimeInterval
    private var cached: String?

    package init(transport: any HTTPTransport, timeout: TimeInterval = 5) {
        self.transport = transport
        self.timeout = timeout
    }

    /// The public IP, or the loopback fallback. Never throws and never blocks
    /// longer than `timeout`.
    package func current() async -> String {
        if let cached { return cached }
        let resolved = await lookup() ?? Self.fallback
        cached = resolved
        return resolved
    }

    /// Resolves ahead of time so the submit path does not pay for the lookup.
    /// Android warms this in `initialize` for the same reason.
    package func warm() async {
        _ = await current()
    }

    private func lookup() async -> String? {
        var request = URLRequest(url: Self.lookupURL)
        request.timeoutInterval = timeout

        guard let (data, response) = try? await transport.send(request),
              (200..<300).contains(response.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = object["ip"] as? String else {
            return nil
        }
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// Matches BrowserInfo's access level, now `package`.
package extension BrowserInfo {
    /// The four fields the backend validates as non-blank.
    ///
    /// Asserted from both the wire-encoding tests and the device-assembly tests,
    /// so a factory that produces a structurally valid but unsubmittable value
    /// cannot pass. The previous test asserted these keys were merely *present*,
    /// which an empty string satisfies — which is how a shipping SDK that could
    /// never submit anything stayed green.
    var isSubmittable: Bool {
        missingRequiredFields.isEmpty
    }

    /// Names of any backend-required field that is blank.
    var missingRequiredFields: [String] {
        var missing: [String] = []
        func check(_ value: String, _ name: String) {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(name)
            }
        }
        check(userAgent, "user_agent")
        check(ipAddress, "ip_address")
        check(language, "language")
        check(acceptHeader, "accept_header")
        return missing
    }
}
