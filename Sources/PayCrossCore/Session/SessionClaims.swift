import Foundation

/// Claims read out of a PayCross session JWT.
///
/// The signature is **not** verified here — it is verified server-side. This
/// decodes the payload only, to learn the session id and the amount to display.
public struct SessionClaims: Sendable, Hashable {
    public let sessionID: String
    public let merchantID: String
    public let customerID: String
    public let brandingID: String?
    public let amount: Amount
    /// Token expiry, epoch seconds.
    public let expiresAt: Int64?

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return Int64(now.timeIntervalSince1970) >= expiresAt
    }
}

public enum SessionTokenError: Error, Sendable, Equatable {
    case empty
    case malformed(String)
    case missingField(String)
}

/// Decodes a PayCross session JWT payload.
public enum SessionTokenDecoder {

    public static func decode(_ token: String) throws -> SessionClaims {
        guard !token.isEmpty else { throw SessionTokenError.empty }

        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw SessionTokenError.malformed("expected 3 dot-separated parts, got \(parts.count)")
        }

        guard let data = base64URLDecode(String(parts[1])) else {
            throw SessionTokenError.malformed("payload is not valid base64url")
        }

        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SessionTokenError.malformed("payload is not a JSON object")
            }
            object = parsed
        } catch let error as SessionTokenError {
            throw error
        } catch {
            throw SessionTokenError.malformed("payload is not valid JSON")
        }

        guard let sessionID = object.nonNullString("sub") else {
            throw SessionTokenError.missingField("sub")
        }
        guard let currency = object.nonNullString("currency") else {
            throw SessionTokenError.missingField("currency")
        }
        guard let amount = object.nonNullInt64("amount") else {
            throw SessionTokenError.missingField("amount")
        }

        return SessionClaims(
            sessionID: sessionID,
            merchantID: object.nonNullString("merchant") ?? "",
            customerID: object.nonNullString("customer") ?? "",
            // Android maps an empty branding string to null; keep that.
            brandingID: object.nonNullString("branding").flatMap { $0.isEmpty ? nil : $0 },
            amount: Amount(minorUnits: amount, currencyCode: currency),
            expiresAt: object.nonNullInt64("exp")
        )
    }

    /// JWT uses base64url without padding; Foundation's decoder needs both fixed.
    static func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }
}

private extension [String: Any] {
    func nonNullString(_ key: String) -> String? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        return value as? String
    }

    func nonNullInt64(_ key: String) -> Int64? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }
}
