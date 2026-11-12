import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MintedSession: Sendable, Equatable {
    public let sessionID: String
    public let sessionToken: String
    public let checkoutURL: String
    public let sessionURL: String
    public let sentBody: String
}

public struct SessionMinter: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let send: Transport

    public init(send: @escaping Transport) {
        self.send = send
    }

    public func mint(
        merchant: Merchant,
        requestBody: String,
        deepLinkReturn: Bool = false,
        timestamp: Int64,
        uuid: String
    ) async throws -> MintedSession {
        let token = try await accessToken(for: merchant)

        let substituted = BodyTemplate.substitute(
            requestBody, timestamp: timestamp, uuid: uuid
        )
        let body = deepLinkReturn
            ? try BodyTemplate.withDeepLinkReturn(substituted)
            : substituted

        return try await postSession(merchant: merchant, token: token, body: body)
    }

    func accessToken(for merchant: Merchant) async throws -> String {
        guard let url = URL(string: merchant.tokenURL) else {
            throw HarnessError.missingField("tokenUrl")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Basic \(basicCredential(merchant))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HarnessError.tokenRequestFailed(response.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String else {
            throw HarnessError.missingField("access_token")
        }
        return token
    }

    func postSession(
        merchant: Merchant,
        token: String,
        body: String
    ) async throws -> MintedSession {
        guard let url = URL(string: merchant.sessionsURL) else {
            throw HarnessError.missingField("paymentApiUrl")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !merchant.paycrossVersion.isEmpty {
            request.setValue(merchant.paycrossVersion, forHTTPHeaderField: "Paycross-Version")
        }
        request.httpBody = Data(body.utf8)

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HarnessError.sessionRequestFailed(
                response.statusCode,
                String(data: data, encoding: .utf8)
            )
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessError.missingField("session response")
        }
        guard let id = object["id"] as? String else {
            throw HarnessError.missingField("id")
        }
        guard let sessionToken = object["session_token"] as? String else {
            throw HarnessError.missingField("session_token")
        }
        guard let checkoutURL = (object["checkout_url"] as? String),
              !checkoutURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HarnessError.missingField("checkout_url")
        }

        let base = merchant.sessionsURL.hasSuffix("/")
            ? String(merchant.sessionsURL.dropLast())
            : merchant.sessionsURL

        return MintedSession(
            sessionID: id,
            sessionToken: sessionToken,
            checkoutURL: checkoutURL,
            sessionURL: "\(base)/\(id)",
            sentBody: body
        )
    }

    func basicCredential(_ merchant: Merchant) -> String {
        Data("\(merchant.clientID):\(merchant.clientSecret)".utf8).base64EncodedString()
    }
}

public enum CurlBuilder {
    public static func mintCommand(merchant: Merchant, body: String) -> String {
        """
        # Set these first; they are deliberately not written into the command.
        # export PAYCROSS_CLIENT_ID=... PAYCROSS_CLIENT_SECRET=...
        AUTH=$(printf '%s:%s' "$PAYCROSS_CLIENT_ID" "$PAYCROSS_CLIENT_SECRET" | openssl base64 -A)

        TOKEN=$(curl -sS -X POST '\(merchant.tokenURL)' \\
          -H "Authorization: Basic $AUTH" \\
          -d 'grant_type=client_credentials' | jq -r .access_token)

        curl -sS -X POST '\(merchant.sessionsURL)' \\
          -H "Authorization: Bearer $TOKEN" \\
          -H 'Content-Type: application/json' \\
          -d '\(body.replacingOccurrences(of: "'", with: "'\\''"))'
        """
    }
}
