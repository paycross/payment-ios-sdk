#if os(iOS)
import Foundation
@testable import PayCrossCore

actor StubTransport: HTTPTransport {
    struct Reply {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
    }

    private var replies: [Reply]
    private(set) var sent: [URLRequest] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(replies: [Reply]) { self.replies = replies }

    init(status: Int = 200, json: String = "{}") {
        self.replies = [Reply(status: status, body: Data(json.utf8))]
    }

    func hasBeenAsked(for count: Int) async {
        guard sent.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        for waiter in waiters where waiter.count <= sent.count { waiter.continuation.resume() }
        waiters.removeAll { $0.count <= sent.count }

        let reply = replies.isEmpty ? Reply() : replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: reply.status, httpVersion: nil, headerFields: nil
        )
        return (reply.body, response ?? HTTPURLResponse())
    }
}
#endif
