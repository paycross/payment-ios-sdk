#if os(iOS)
import SwiftUI
import UIKit
import PayCrossCore

/// Presents the PayCross payment flow.
///
/// ```swift
/// PayCrossAPI.configure(environment: .sandbox)
/// let sheet = PaymentSheet(sessionToken: token)
/// switch await sheet.present(from: viewController) {
/// case .succeeded(let id, _, let amount): …
/// case .failed(_, let recovery) where recovery.isRetryable: …
/// case .failed: …
/// case .cancelled: …
/// }
/// ```
///
/// Nothing here throws: a decline is `.failed`, not a Swift `Error`, so the happy
/// path needs no `catch` and the compiler still checks the recovery branch.
@MainActor
public final class PaymentSheet {
    private let sessionToken: String
    private let savedCards: [SavedCard]

    public init(sessionToken: String, savedCards: [SavedCard] = []) {
        self.sessionToken = sessionToken
        self.savedCards = savedCards
    }

    /// Presents the sheet and resolves when the payment reaches a terminal state
    /// or the shopper dismisses it.
    public func present(from presenter: UIViewController) async -> PaymentResult {
        guard let configuration = PayCrossAPI.configuration, configuration.environment.isUsable else {
            assertionFailure("PayCrossAPI.configure(environment:) must be called first")
            return .failed(transactionID: nil, recovery: .contactSupport)
        }

        let claims: SessionClaims
        do {
            claims = try SessionTokenDecoder.decode(sessionToken)
        } catch {
            return .failed(transactionID: nil, recovery: .restart)
        }

        if claims.isExpired() {
            return .failed(transactionID: nil, recovery: .restart)
        }

        let model = PaymentSheetModel(
            sessionToken: sessionToken,
            claims: claims,
            savedCards: savedCards,
            configuration: configuration
        )

        let host = PaymentHostController(model: model)
        // The shopper must not be able to swipe the sheet away mid-authorization.
        host.isModalInPresentation = true
        model.threeDSPresenter = WebKitThreeDSPresenter(host: host)
        presenter.present(host, animated: true)

        let result = await model.awaitResult()
        await host.dismissSelf()
        return result
    }
}

/// Hosts the SwiftUI form and applies the platform hardening.
@MainActor
final class PaymentHostController: UIHostingController<PaymentSheetView> {

    init(model: PaymentSheetModel) {
        super.init(rootView: PaymentSheetView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func dismissSelf() async {
        await withCheckedContinuation { continuation in
            guard presentingViewController != nil else {
                return continuation.resume()
            }
            dismiss(animated: true) { continuation.resume() }
        }
    }
}

/// Owns the form state and drives the flow.
@MainActor
final class PaymentSheetModel: ObservableObject {
    @Published var form: CardFormState
    @Published private(set) var isLoading = false

    let claims: SessionClaims
    let savedCards: [SavedCard]

    private let sessionToken: String
    private let configuration: Configuration
    private var continuation: CheckedContinuation<PaymentResult, Never>?
    /// Set once the host controller exists, since the presenter needs somewhere
    /// to attach its web view.
    var threeDSPresenter: (any ThreeDSPresenting)?

    init(
        sessionToken: String,
        claims: SessionClaims,
        savedCards: [SavedCard],
        configuration: Configuration
    ) {
        self.sessionToken = sessionToken
        self.claims = claims
        self.savedCards = savedCards
        self.configuration = configuration

        var initial = CardFormState(source: savedCards.first.map { .saved($0) } ?? .newCard)
        // Prefill is a test convenience and is nil in production by construction.
        if let prefill = configuration.effectiveTestCardPrefill {
            CardFormReducer.reduce(state: &initial, event: .nameChanged(prefill.cardholderName))
            CardFormReducer.reduce(state: &initial, event: .panChanged(prefill.pan))
            CardFormReducer.reduce(
                state: &initial,
                event: .expiryChanged(prefill.expireMonth + String(prefill.expireYear.suffix(2)))
            )
            CardFormReducer.reduce(state: &initial, event: .cvvChanged(prefill.cvv))
            initial.saveCard = prefill.saveCard
        }
        self.form = initial
    }

    var amount: Amount { claims.amount }

    func awaitResult() async -> PaymentResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    func pay() {
        guard let card = form.cardData(), !isLoading else { return }
        isLoading = true
        // Clears the CVV from form state the moment it is handed off (Req 3.3.1).
        CardFormReducer.reduce(state: &form, event: .paySubmitted)

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.runFlow(with: card)
            switch outcome {
            case .finished(let result):
                self.finish(result)
            case .reArmForm(let message):
                self.isLoading = false
                CardFormReducer.reduce(state: &self.form, event: .declined(message: message))
            }
        }
    }

    private func runFlow(with card: CardData) async -> FlowOutcome {
        let client = PayCrossAPIClient(
            baseURL: configuration.environment.baseURL,
            transport: URLSessionTransport(),
            userAgent: "PayCrossSDK-iOS/\(PayCrossAPI.version)"
        )
        let runner = PaymentFlowRunner(
            client: client,
            // If the presenter is missing the sheet has no host, so a 3DS step
            // could not be shown. Reporting .failed rather than .completed keeps
            // an unanswered challenge from looking like an answered one.
            presenter: threeDSPresenter ?? ThreeDSPresenterStub(),
            claims: claims
        )
        let request = SubmitCardRequest(
            session: sessionToken,
            card: card,
            browserInfo: DeviceInfo.browserInfo()
        )
        return await runner.run(request)
    }

    private func finish(_ result: PaymentResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Placeholder until the WebKit 3DS layer lands. Reports failure rather than
/// silently succeeding, so a 3DS session cannot appear to pass without one.
private struct ThreeDSPresenterStub: ThreeDSPresenting {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome { .failed }
    func dismiss() async {}
}

/// Collects the device characteristics 3DS v2 requires.
enum DeviceInfo {
    @MainActor
    static func browserInfo(ipAddress: String = "") -> BrowserInfo {
        let screen = UIScreen.main.bounds
        return BrowserInfo(
            userAgent: "PayCrossSDK-iOS/\(PayCrossAPI.version)",
            ipAddress: ipAddress,
            screenWidth: Int(screen.width),
            screenHeight: Int(screen.height),
            timezoneOffset: BrowserInfo.timezoneOffsetMinutes(),
            language: Locale.current.identifier
        )
    }
}

struct PaymentSheetView: View {
    @ObservedObject var model: PaymentSheetModel

    var body: some View {
        NavigationStack {
            CardFormView(
                state: $model.form,
                amount: model.amount,
                savedCards: model.savedCards,
                allowsSaving: true,
                isLoading: model.isLoading,
                onPay: model.pay
            )
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel)
                        .disabled(model.isLoading)
                }
            }
        }
    }
}
#endif
