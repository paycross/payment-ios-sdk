import Foundation

/// URL and form handling for 3DS steps.
///
/// Deliberately in Core: deciding when a navigation means "the challenge is
/// finished" is the part that goes wrong, and it is pure string work, so it is
/// asserted on Linux rather than needing a simulator and a live ACS.
package enum ThreeDSNavigation {

    /// A navigation back to one of our hosts signals completion.
    package static let returnHostSuffixes = ["pay-cross.com", "test-pay-cross.com"]

    /// EMV 3DS requires exact form field names, but providers emit variants
    /// (Nuvei sends `cReq`). Normalised the same way the checkout page does.
    static let fieldNormalisation = [
        "cReq": "creq",
        "CReq": "creq",
        "threeds_method_data": "threeDSMethodData"
    ]

    /// Whether `url` is a navigation back to a PayCross host.
    package static func isReturnURL(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return returnHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Whether `url` means the 3DS step finished.
    ///
    /// The action URL itself is excluded: for the sandbox provider the simulated
    /// ACS is hosted on our own domain, so without this the step would complete
    /// on its own initial load and the shopper would never see the challenge.
    package static func isCompletionURL(_ url: String, actionURL: String) -> Bool {
        let normalise = { (value: String) in
            String(value.reversed().drop(while: { $0 == "/" }).reversed())
        }
        return normalise(url) != normalise(actionURL) && isReturnURL(url)
    }

    /// Builds an `application/x-www-form-urlencoded` body for a form-POST action.
    ///
    /// Empty values are dropped, matching Android — an ACS rejects a `creq` that
    /// is present but blank differently from one that is absent.
    package static func encodeFormBody(_ data: [String: String]?) -> String {
        guard let data, !data.isEmpty else { return "" }

        return data
            .filter { !$0.value.isEmpty }
            // Sorted so the body is deterministic and therefore assertable.
            .sorted { $0.key < $1.key }
            .map { key, value in
                let name = fieldNormalisation[key] ?? key
                return "\(formURLEncode(name))=\(formURLEncode(value))"
            }
            .joined(separator: "&")
    }

    /// Matches Java's `URLEncoder.encode` so bodies are byte-identical to Android:
    /// unreserved characters pass through, a space becomes `+`, the rest are
    /// percent-encoded.
    static func formURLEncode(_ value: String) -> String {
        var out = ""
        for byte in Array(value.utf8) {
            let character = Character(UnicodeScalar(byte))
            switch character {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "*", "_":
                out.append(character)
            case " ":
                out.append("+")
            default:
                out.append(String(format: "%%%02X", byte))
            }
        }
        return out
    }
}
