import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The transport the API client sends over.
///
/// A protocol rather than a bare `URLSession` so the whole client is asserted on
/// Linux against a stub, with no server and no `URLProtocol` subclassing.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum PayCrossError: Error, Sendable, Equatable {
    /// The SDK was used before `configure` was called, or with an unusable environment.
    case notConfigured
    /// Transport failure — no response, or the connection dropped.
    case transport(String)
    /// The server answered, but not with 2xx.
    case http(status: Int, body: String?)
    /// The session JWT was rejected.
    case sessionExpired
    /// The response body did not decode.
    case decoding(String)

    /// Whether a submit should be retried after this error.
    ///
    /// Only server-side rejections are retried; a transport failure or a timeout
    /// is not, because the request may well have been received.
    public var isRetryableRejection: Bool {
        if case .http(let status, _) = self { return status == 409 }
        return false
    }
}

/// Client for the PayCross public checkout API.
public struct PayCrossAPIClient: Sendable {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let userAgent: String
    private let makeIdempotencyKey: @Sendable () -> String

    public init(
        baseURL: URL,
        transport: HTTPTransport,
        userAgent: String,
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.userAgent = userAgent
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    /// `GET session/{sessionID}` — session status, latest transaction and checkout data.
    public func session(id: String, sessionToken: String) async throws -> SessionResponse {
        var request = makeRequest(path: ["session", id], method: "GET")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    /// `POST submit-card`
    ///
    /// The idempotency key is generated once per *logical* submission and reused
    /// across retry-after loops, so a retry cannot create a second transaction.
    public func submitCard(
        _ body: SubmitCardRequest,
        idempotencyKey: String
    ) async throws -> SubmitCardResponse {
        var request = makeRequest(path: ["submit-card"], method: "POST")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw PayCrossError.decoding("could not encode submit body")
        }
        return try await perform(request)
    }

    /// `GET status/{transactionID}`
    public func status(transactionID: String) async throws -> StatusResponse {
        try await perform(makeRequest(path: ["status", transactionID], method: "GET"))
    }

    public func newIdempotencyKey() -> String { makeIdempotencyKey() }

    // MARK: - Plumbing

    private func makeRequest(path: [String], method: String) -> URLRequest {
        // appendingPathComponent percent-encodes each segment, so a hostile
        // transaction id cannot climb out of the path.
        let url = path.reduce(baseURL) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as PayCrossError {
            throw error
        } catch {
            throw PayCrossError.transport(error.localizedDescription)
        }

        if response.statusCode == 401 { throw PayCrossError.sessionExpired }
        guard (200..<300).contains(response.statusCode) else {
            throw PayCrossError.http(
                status: response.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PayCrossError.decoding("\(T.self): \(error)")
        }
    }
}

/// `URLSession`-backed transport.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PayCrossError.transport("response was not HTTP")
        }
        return (data, http)
    }
}
