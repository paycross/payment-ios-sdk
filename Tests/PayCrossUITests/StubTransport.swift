#if os(iOS)
import Foundation
@testable import PayCrossCore

/// Answers canned replies and records what it was asked to send.
///
/// The same shape as the stub `APIClientTests` uses in Core, so both targets
/// fake the transport the same way. Shared across this target's files because
/// the model's transport seam is what keeps a unit test from opening a socket
/// to the live checkout API.
actor StubTransport: HTTPTransport {
    struct Reply {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
    }

    private var replies: [Reply]
    private(set) var sent: [URLRequest] = []

    init(replies: [Reply]) { self.replies = replies }

    init(status: Int = 200, json: String = "{}") {
        self.replies = [Reply(status: status, body: Data(json.utf8))]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        let reply = replies.isEmpty ? Reply() : replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: reply.status, httpVersion: nil, headerFields: nil
        )
        return (reply.body, response ?? HTTPURLResponse())
    }
}
#endif
