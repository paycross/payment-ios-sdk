import XCTest
@testable import PayCrossCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor ScriptedTransport: HTTPTransport {
    struct Reply {
        var status: Int = 200
        var json: String
    }

    private var submitReplies: [Reply]
    private var statusReplies: [Reply]
    private(set) var submitCount = 0
    private(set) var statusCount = 0
    private(set) var idempotencyKeys: [String] = []

    init(submit: [Reply] = [], status: [Reply] = []) {
        self.submitReplies = submit
        self.statusReplies = status
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let reply: Reply

        if path.contains("submit-card") {
            submitCount += 1
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                idempotencyKeys.append(key)
            }
            reply = submitReplies.isEmpty ? Reply(json: "{}") : submitReplies.removeFirst()
        } else {
            statusCount += 1
            if statusReplies.count > 1 {
                reply = statusReplies.removeFirst()
            } else {
                reply = statusReplies.first ?? Reply(json: #"{"transaction_id":"t","status":"pending"}"#)
            }
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil
        )!
        return (Data(reply.json.utf8), response)
    }
}

private actor VirtualScheduler: FlowScheduler {
    private var consumed: Duration = .zero
    private(set) var sleeps: [Duration] = []

    func sleep(for duration: Duration) async throws {
        sleeps.append(duration)
        consumed += duration
    }

    func elapsed() async -> Duration { consumed }
}

private actor CancellingScheduler: FlowScheduler {
    private var consumed: Duration = .zero
    private var sleeps = 0
    private let cancelsOnSleep: Int
    private var run: Task<FlowOutcome, Never>?

    init(cancelsOnSleep: Int) { self.cancelsOnSleep = cancelsOnSleep }

    func runUntilCancelled(
        _ body: @escaping @Sendable () async -> FlowOutcome
    ) async -> FlowOutcome {
        let task = Task(operation: body)
        run = task
        return await task.value
    }

    func sleep(for duration: Duration) async throws {
        sleeps += 1
        if sleeps == cancelsOnSleep { run?.cancel() }
        try Task.checkCancellation()
        consumed += duration
    }

    func elapsed() async -> Duration { consumed }
}

private actor RecordingPresenter: ThreeDSPresenting {
    private let outcome: ThreeDSOutcome
    private(set) var presented: [ThreeDSStep] = []
    private(set) var dismissals = 0

    init(outcome: ThreeDSOutcome = .completed) {
        self.outcome = outcome
    }

    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome {
        presented.append(step)
        return outcome
    }

    func dismiss() async { dismissals += 1 }
}

private struct NeverResolvingPresenter: ThreeDSPresenting {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return .completed
    }

    func dismiss() async {}
}

final class PaymentFlowRunnerTests: XCTestCase {

    private let baseURL = URL(string: "https://checkout.test-pay-cross.com/api")!

    private func makeRunner(
        transport: ScriptedTransport,
        scheduler: any FlowScheduler,
        presenter: any ThreeDSPresenting,
        messages: FlowMessages = .english
    ) -> PaymentFlowRunner {
        PaymentFlowRunner(
            client: PayCrossAPIClient(baseURL: baseURL, transport: transport, userAgent: "test"),
            presenter: presenter,
            scheduler: scheduler,
            claims: SessionClaims(
                sessionID: "s", merchantID: "m", customerID: "c", brandingID: nil,
                amount: Amount(minorUnits: 1000, currencyCode: "EUR"), expiresAt: nil
            ),
            messages: messages
        )
    }

    // MARK: - The sheet's own words

    private var frenchMessages: FlowMessages {
        FlowMessages(
            paymentFailed: "Le paiement a échoué. Veuillez réessayer.",
            networkError: "Erreur réseau. Veuillez réessayer.",
            submissionFailed: "Échec de l'envoi du paiement"
        )
    }

    func testSubmitFailureSpeaksTheLanguageTheSheetResolved() async {
        let replies = Array(
            repeating: ScriptedTransport.Reply(json: #"{"success":false,"retry_after":1}"#),
            count: 10
        )
        let runner = makeRunner(
            transport: ScriptedTransport(submit: replies),
            scheduler: VirtualScheduler(),
            presenter: RecordingPresenter(),
            messages: frenchMessages
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .reArmForm(message: "Échec de l'envoi du paiement"))
    }

    func testARetryableDeclineSpeaksTheLanguageTheSheetResolved() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [.init(json: #"{"transaction_id":"t1","status":"failed","recovery":"retry"}"#)]
        )
        let runner = makeRunner(
            transport: transport,
            scheduler: VirtualScheduler(),
            presenter: RecordingPresenter(),
            messages: frenchMessages
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .reArmForm(message: "Le paiement a échoué. Veuillez réessayer."))
    }

    private var sampleRequest: SubmitCardRequest {
        SubmitCardRequest(
            session: "jwt",
            card: .newCard(
                cardholderName: "A PERSON", pan: "4111111111111111",
                expireMonth: "12", expireYear: "2030", cvv: "123"
            ),
            browserInfo: BrowserInfo(
                userAgent: "ua", ipAddress: "192.0.2.1", screenWidth: 390,
                screenHeight: 844, timezoneOffset: 0, language: "en"
            )
        )
    }

    func testHappyPathSubmitsThenPollsToSuccess() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(json: #"{"transaction_id":"t1","status":"pending"}"#),
                .init(json: #"{"transaction_id":"t1","status":"success","amount":1000,"currency":"EUR"}"#)
            ]
        )
        let scheduler = VirtualScheduler()
        let runner = makeRunner(transport: transport, scheduler: scheduler, presenter: RecordingPresenter())

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .finished(.succeeded(
            transactionID: "t1", status: "success",
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            savedCardToken: nil
        )))
        let statusCount = await transport.statusCount
        XCTAssertEqual(statusCount, 2)
    }

    func testRetryAfterLoopReusesOneIdempotencyKey() async {
        let transport = ScriptedTransport(
            submit: [
                .init(json: #"{"success":false,"retry_after":3}"#),
                .init(json: #"{"success":false,"retry_after":2}"#),
                .init(json: #"{"success":true,"transaction_id":"t1"}"#)
            ],
            status: [.init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)]
        )
        let scheduler = VirtualScheduler()
        let runner = makeRunner(transport: transport, scheduler: scheduler, presenter: RecordingPresenter())

        _ = await runner.run(sampleRequest)

        let keys = await transport.idempotencyKeys
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(Set(keys).count, 1, "a retry must not mint a new idempotency key")

        let sleeps = await scheduler.sleeps
        XCTAssertEqual(sleeps.first, .seconds(3), "must honour the server's retry_after")
    }

    func testSubmitGivesUpAfterMaxAttempts() async {
        let replies = Array(
            repeating: ScriptedTransport.Reply(json: #"{"success":false,"retry_after":1}"#),
            count: 10
        )
        let transport = ScriptedTransport(submit: replies)
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .reArmForm(message: "Payment submission failed"))
        let submitCount = await transport.submitCount
        XCTAssertEqual(submitCount, FlowLimits.maxSubmitAttempts)
    }

    func testSubmitErrorReArmsTheFormWithTheServerMessage() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":false,"error":"Card declined"}"#)]
        )
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .reArmForm(message: "Card declined"))
        let submitCount = await transport.submitCount
        XCTAssertEqual(submitCount, 1, "a plain rejection is not retried")
    }

    // MARK: - 3DS

    func testChallengeIsPresentedThenPollingContinuesToSuccess() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(json: """
                {"transaction_id":"t1","status":"threeds_challenge",
                 "action":{"url":"https://acs/ch","method":"GET"}}
                """),
                .init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)
            ]
        )
        let presenter = RecordingPresenter(outcome: .completed)
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: presenter
        )

        let outcome = await runner.run(sampleRequest)

        let presented = await presenter.presented
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(presented[0].isChallenge)
        guard case .finished(.succeeded) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
    }

    func testRepeatedIdenticalChallengeIsPresentedOnlyOnce() async {
        let challenge = """
        {"transaction_id":"t1","status":"threeds_challenge",
         "action":{"url":"https://acs/ch","method":"POST","data":{"b":"2","a":"1"}}}
        """
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(json: challenge),
                .init(json: challenge),
                .init(json: challenge),
                .init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)
            ]
        )
        let presenter = RecordingPresenter(outcome: .completed)
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: presenter
        )

        _ = await runner.run(sampleRequest)

        let presented = await presenter.presented
        XCTAssertEqual(presented.count, 1, "the same action must be presented once")
    }

    func testPollingContinuesWhileAChallengeIsOnScreen() async {
        let challenge = """
        {"transaction_id":"t1","status":"threeds_challenge",
         "action":{"url":"https://acs/ch","method":"GET"}}
        """
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(json: challenge),
                .init(json: challenge),
                .init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)
            ]
        )
        let runner = makeRunner(
            transport: transport,
            scheduler: VirtualScheduler(),
            presenter: NeverResolvingPresenter()
        )

        let outcome = await runner.run(sampleRequest)

        guard case .finished(.succeeded) = outcome else {
            return XCTFail("polling stalled behind the challenge; got \(outcome)")
        }
    }

    // MARK: - Declines

    func testRetryableDeclineReArmsTheFormAndStopsPolling() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [.init(json: #"{"transaction_id":"t1","status":"failed","recovery":"retry"}"#)]
        )
        let scheduler = VirtualScheduler()
        let runner = makeRunner(
            transport: transport, scheduler: scheduler, presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .reArmForm(message: "Payment failed. Please try again."))
        let statusCount = await transport.statusCount
        XCTAssertEqual(statusCount, 1)
        let elapsed = await scheduler.elapsed()
        XCTAssertLessThan(elapsed, FlowLimits.pollDeadline)
    }

    func testNonRetryableDeclineFinishes() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [.init(json: #"{"transaction_id":"t1","status":"failed","recovery":"do_not_retry"}"#)]
        )
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)
        XCTAssertEqual(outcome, .finished(.failed(transactionID: "t1", recovery: .doNotRetry)))
    }

    func testRetryAfterDoesNotEatThePollBudget() async {
        let transport = ScriptedTransport(
            submit: [
                .init(json: #"{"success":false,"retry_after":120}"#),
                .init(json: #"{"success":false,"retry_after":120}"#),
                .init(json: #"{"success":false,"retry_after":120}"#),
                .init(json: #"{"success":false,"retry_after":120}"#),
                .init(json: #"{"success":true,"transaction_id":"t1"}"#)
            ],
            status: [.init(json: #"{"transaction_id":"t1","status":"pending"}"#)]
        )
        let scheduler = VirtualScheduler()
        let runner = makeRunner(
            transport: transport, scheduler: scheduler, presenter: RecordingPresenter()
        )

        _ = await runner.run(sampleRequest)

        let statusCount = await transport.statusCount
        XCTAssertEqual(statusCount, 240, "the poll loop lost its budget to retry_after")
    }

    func testResumePollsWithoutSubmitting() async {
        let transport = ScriptedTransport(
            status: [.init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)]
        )
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: RecordingPresenter()
        )

        let outcome = await runner.resume(transactionID: "t1")

        let submitCount = await transport.submitCount
        XCTAssertEqual(submitCount, 0, "resuming must never create a second transaction")
        guard case .finished(.succeeded) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
    }

    // MARK: - Deadline and transients

    func testPollingGivesUpAtTheDeadline() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [.init(json: #"{"transaction_id":"t1","status":"pending"}"#)]
        )
        let scheduler = VirtualScheduler()
        let runner = makeRunner(
            transport: transport, scheduler: scheduler, presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .finished(.pending(transactionID: "t1", reason: .pollTimeout)))
        let statusCount = await transport.statusCount
        XCTAssertEqual(statusCount, 240)
    }

    func testTransientStatusErrorsKeepPolling() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(status: 404, json: #"{"error":"not found"}"#),
                .init(status: 500, json: #"{"error":"boom"}"#),
                .init(json: #"{"transaction_id":"t1","status":"success","amount":1,"currency":"EUR"}"#)
            ]
        )
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: RecordingPresenter()
        )

        let outcome = await runner.run(sampleRequest)
        guard case .finished(.succeeded) = outcome else {
            return XCTFail("transient errors must not end the payment, got \(outcome)")
        }
    }

    func testResolvedThreeDSStepIsDismissedBeforeTheFlowEnds() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [
                .init(json: """
                {"transaction_id":"t1","status":"threeds_challenge",
                 "action":{"url":"https://acs/ch","method":"GET"}}
                """),
                .init(json: #"{"transaction_id":"t1","status":"pending"}"#)
            ]
        )
        let presenter = RecordingPresenter(outcome: .completed)
        let runner = makeRunner(
            transport: transport, scheduler: VirtualScheduler(), presenter: presenter
        )

        let outcome = await runner.run(sampleRequest)

        XCTAssertEqual(outcome, .finished(.pending(transactionID: "t1", reason: .pollTimeout)))
        for _ in 0..<100 { await Task.yield() }
        let dismissals = await presenter.dismissals
        XCTAssertEqual(dismissals, 1, "an answered 3DS step must be torn down when it resolves")
    }

    func testCancellingBeforeATransactionExistsCarriesNoID() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":false,"retry_after":30}"#)],
            status: []
        )
        let scheduler = CancellingScheduler(cancelsOnSleep: 1)
        let runner = makeRunner(
            transport: transport, scheduler: scheduler, presenter: RecordingPresenter()
        )

        let request = sampleRequest
        let outcome = await scheduler.runUntilCancelled { await runner.run(request) }

        XCTAssertEqual(outcome, .finished(.cancelled(transactionID: nil)))
        let submits = await transport.submitCount
        XCTAssertEqual(
            submits, 1,
            "a cancellation that lands after a second attempt pins nothing this test is about"
        )
    }

    func testCancellingStopsPollingAndTearsDown3DS() async {
        let transport = ScriptedTransport(
            submit: [.init(json: #"{"success":true,"transaction_id":"t1"}"#)],
            status: [.init(json: #"{"transaction_id":"t1","status":"pending"}"#)]
        )
        let presenter = RecordingPresenter()
        let scheduler = CancellingScheduler(cancelsOnSleep: 2)
        let runner = makeRunner(
            transport: transport, scheduler: scheduler, presenter: presenter
        )

        let request = sampleRequest
        let outcome = await scheduler.runUntilCancelled { await runner.run(request) }

        XCTAssertEqual(
            outcome, .finished(.cancelled(transactionID: "t1")),
            "a cancelled payment leaves a transaction behind; the host has to be able to name it"
        )

        let polls = await transport.statusCount
        XCTAssertEqual(
            polls, 2,
            "polling must stop on cancellation, not spin out the remaining deadline"
        )

        let dismissals = await presenter.dismissals
        XCTAssertEqual(
            dismissals, 1,
            "stopped() must call dismiss() unconditionally - it cannot know whether a step is on screen"
        )
    }
}
