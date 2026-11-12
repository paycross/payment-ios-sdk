import Foundation

package enum ThreeDSNavigation {
    package static let returnHostSuffixes = ["pay-cross.com", "test-pay-cross.com"]

    // EMV 3DS requires exact form field names, but some providers send variants such as `cReq`.
    static let fieldNormalisation = [
        "cReq": "creq",
        "CReq": "creq",
        "threeds_method_data": "threeDSMethodData"
    ]

    package static func isReturnURL(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return returnHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    package static func isCompletionURL(_ url: String, actionURL: String) -> Bool {
        let normalise = { (value: String) in
            String(value.reversed().drop(while: { $0 == "/" }).reversed())
        }
        return normalise(url) != normalise(actionURL) && isReturnURL(url)
    }

    package static func encodeFormBody(_ data: [String: String]?) -> String {
        guard let data, !data.isEmpty else { return "" }

        return data
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { key, value in
                let name = fieldNormalisation[key] ?? key
                return "\(formURLEncode(name))=\(formURLEncode(value))"
            }
            .joined(separator: "&")
    }

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
