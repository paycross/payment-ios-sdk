#if os(iOS)
import SwiftUI
import UIKit
import WebKit
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

    /// Saved cards, field groups and whether saving is offered all come from the
    /// session, not from the integrator — the server decides what this checkout
    /// may show. An earlier version took `savedCards` as a parameter, which put
    /// the merchant app in charge of something it does not own.
    public init(sessionToken: String) {
        self.sessionToken = sessionToken
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
    /// True until the session has been fetched; the form cannot be shown before
    /// then because the server decides what it contains.
    @Published private(set) var isPreparing = true
    @Published private(set) var sessionData: SessionData?
    @Published var fieldValues: [String: [String: String]] = [:]
    @Published private(set) var fieldErrors: [FieldGroupError] = []

    let claims: SessionClaims

    var savedCards: [SavedCard] {
        sessionData?.savedCards?.map(\.presentable) ?? []
    }

    var allowsSavingCard: Bool {
        sessionData?.allowsSavingCard ?? false
    }

    var fieldGroups: [FieldGroup] {
        sessionData?.fieldGroups ?? []
    }

    private let sessionToken: String
    private let configuration: Configuration
    private var continuation: CheckedContinuation<PaymentResult, Never>?
    /// Set once the host controller exists, since the presenter needs somewhere
    /// to attach its web view.
    var threeDSPresenter: (any ThreeDSPresenting)?
    private lazy var ipProvider = IPAddressProvider(transport: URLSessionTransport())

    init(
        sessionToken: String,
        claims: SessionClaims,
        configuration: Configuration
    ) {
        self.sessionToken = sessionToken
        self.claims = claims
        self.configuration = configuration

        var initial = CardFormState(source: .newCard)
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

    private func makeClient() -> PayCrossAPIClient {
        PayCrossAPIClient(
            baseURL: configuration.environment.baseURL,
            transport: URLSessionTransport(),
            userAgent: "PayCrossSDK-iOS/\(PayCrossAPI.version)"
        )
    }

    /// Fetches the session and acts on what it says.
    ///
    /// A completed session must never render the form: the shopper would pay a
    /// second time, and the new idempotency key gives the backend nothing to
    /// relate the two submissions by.
    func load() async {
        // Warmed off the critical path so submit does not pay for the lookup.
        async let ip: Void = ipProvider.warm()
        async let ua: Void = DeviceInfo.warmUserAgent()
        _ = await (ip, ua)

        let response = try? await makeClient()
            .session(id: claims.sessionID, sessionToken: sessionToken)

        switch SessionResolver.resolve(response, claims: claims) {
        case .finish(let result):
            isPreparing = false
            finish(result)

        case .resume(let transactionID):
            // A transaction already exists. Poll it rather than creating another.
            isPreparing = false
            isLoading = true
            let outcome = await makeRunner().resume(transactionID: transactionID)
            switch outcome {
            case .finished(let result):
                finish(result)
            case .reArmForm(let message):
                isLoading = false
                applySessionData(response?.data)
                CardFormReducer.reduce(state: &form, event: .declined(message: message))
            }

        case .showForm(let data):
            applySessionData(data)
            isPreparing = false
        }
    }

    private func applySessionData(_ data: SessionData?) {
        guard let data else { return }
        sessionData = data
        fieldValues = FieldGroupLogic.initialValues(data.fieldGroups ?? [])
        // Android initialises the selection to null and shows "Use a new card";
        // auto-selecting a stored card is one unnoticed tap from charging it.
    }

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

        // Server-driven fields are validated here, not in the form reducer: only
        // visible fields count, and visibility depends on sibling values.
        fieldErrors = FieldGroupLogic.validate(groups: fieldGroups, values: fieldValues)
        guard fieldErrors.isEmpty else { return }

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

    private func makeRunner() -> PaymentFlowRunner {
        PaymentFlowRunner(
            client: makeClient(),
            // If the presenter is missing the sheet has no host, so a 3DS step
            // could not be shown. Reporting .failed rather than .completed keeps
            // an unanswered challenge from looking like an answered one.
            presenter: threeDSPresenter ?? ThreeDSPresenterStub(),
            claims: claims
        )
    }

    private func runFlow(with card: CardData) async -> FlowOutcome {
        let runner = makeRunner()
        let request = SubmitCardRequest(
            session: sessionToken,
            card: card,
            browserInfo: DeviceInfo.browserInfo(ipAddress: await ipProvider.current()),
            // Only visible, non-blank values go on the wire; a hidden field's
            // stale value must not be submitted.
            fieldGroups: FieldGroupLogic.submissionValues(
                groups: fieldGroups, values: fieldValues
            ).nilIfEmpty
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
///
/// Every field here is validated non-blank by the backend, so this is assembled
/// from real values rather than placeholders and asserted by
/// `BrowserInfo.isSubmittable`.
@MainActor
enum DeviceInfo {

    /// The real device user agent, which the ACS fingerprints against.
    ///
    /// Android sends `WebSettings.getDefaultUserAgent(context)`; sending the SDK
    /// version string instead is a value the backend accepts and the ACS does
    /// not recognise, which raises the odds of a forced challenge.
    private static var cachedUserAgent: String?

    static func warmUserAgent() async {
        guard cachedUserAgent == nil else { return }
        let webView = WKWebView(frame: .zero)
        cachedUserAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
    }

    static func browserInfo(ipAddress: String) -> BrowserInfo {
        let bounds = screenBounds()
        let scale = UITraitCollection.current.displayScale
        return BrowserInfo(
            userAgent: cachedUserAgent ?? defaultUserAgent,
            ipAddress: ipAddress,
            // Pixels, not points: 3DS specifies browserScreenWidth in pixels and
            // Android sends displayMetrics.widthPixels.
            screenWidth: Int(bounds.width * scale),
            screenHeight: Int(bounds.height * scale),
            timezoneOffset: BrowserInfo.timezoneOffsetMinutes(),
            // BCP-47 ("en-GB"), not the ICU identifier ("en_GB") that
            // Locale.identifier returns — clamped, because a device whose
            // Region differs from the language's home region yields a tag with
            // extension subtags ("en-US-u-rg-lvzzzz") that the backend rejects.
            language: BrowserInfo.clampedLanguageTag(Locale.current.identifier(.bcp47))
        )
    }

    /// Used only until the real user agent resolves; still non-blank so a
    /// submission is never rejected outright for want of it.
    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) PayCrossSDK-iOS/\(PayCrossAPI.version)"

    private static func screenBounds() -> CGRect {
        // UIScreen.main is deprecated in iOS 16; read the active scene instead.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
}

struct PaymentSheetView: View {
    @ObservedObject var model: PaymentSheetModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isPreparing {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CardFormView(
                        state: $model.form,
                        amount: model.amount,
                        savedCards: model.savedCards,
                        allowsSaving: model.allowsSavingCard,
                        isLoading: model.isLoading,
                        fieldGroups: model.fieldGroups,
                        fieldValues: $model.fieldValues,
                        fieldErrors: model.fieldErrors,
                        onPay: model.pay
                    )
                }
            }
            .task { await model.load() }
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

private extension Dictionary {
    /// Sends nothing rather than an empty object when there is nothing to send.
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
