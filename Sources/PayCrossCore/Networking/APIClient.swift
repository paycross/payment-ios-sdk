import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

package protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

package enum PayCrossError: Error, Sendable, Equatable {
    case notConfigured
    case transport(String)
    case http(status: Int, body: String?)
    case sessionExpired
    // On a saved card this is a failed ownership check, so it must not be retried.
    case notFound
    case decoding(String)

    package var serverMessage: String? {
        if case .http(_, let body) = self { return body }
        return nil
    }

    // A transport failure is not retried, because the server may already have the request.
    package var isRetryableRejection: Bool {
        if case .http(let status, _) = self { return status == 409 }
        return false
    }
}

package struct PayCrossAPIClient: Sendable {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let userAgent: String
    private let makeIdempotencyKey: @Sendable () -> String

    package init(
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

    package func session(id: String, sessionToken: String) async throws -> SessionResponse {
        var request = makeRequest(path: ["session", id], method: "GET")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    // One idempotency key per logical submission, so a retry cannot create a second transaction.
    package func submitCard(
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

    package func status(transactionID: String) async throws -> StatusResponse {
        try await perform(makeRequest(path: ["status", transactionID], method: "GET"))
    }

    // The server answers 204 whether or not the card is still active, so a repeat delete is not an error.
    package func deleteSavedCard(uuid: String, sessionToken: String) async throws {
        var request = makeRequest(path: ["saved-cards", uuid], method: "DELETE")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        try await performNoContent(request)
    }

    package func newIdempotencyKey() -> String { makeIdempotencyKey() }

    // MARK: - Plumbing

    private func makeRequest(path: [String], method: String) -> URLRequest {
        // appendingPathComponent percent-encodes each segment, so an id cannot leave its path.
        let url = path.reduce(baseURL) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A cached status response can freeze polling on a stale value, so no payments call is cache-served.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as PayCrossError {
            throw error
        } catch {
            throw PayCrossError.transport(error.localizedDescription)
        }
    }

    private func check(_ response: HTTPURLResponse, body: Data) throws {
        if response.statusCode == 401 { throw PayCrossError.sessionExpired }
        guard (200..<300).contains(response.statusCode) else {
            throw PayCrossError.http(
                status: response.statusCode,
                body: String(data: body, encoding: .utf8)
            )
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await send(request)
        try check(response, body: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PayCrossError.decoding("\(T.self): \(error)")
        }
    }

    // The status poll answers 404 while its row is being written, so 404 is not mapped in check.
    private func performNoContent(_ request: URLRequest) async throws {
        let (data, response) = try await send(request)
        if response.statusCode == 404 { throw PayCrossError.notFound }
        try check(response, body: data)
    }
}

package struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    // Built inline, because a default argument must be as accessible as the initializer it is in.
    package init(session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Payments responses must not be written to URLCache.
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()) {
        self.session = session
    }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PayCrossError.transport("response was not HTTP")
        }
        return (data, http)
    }
}
