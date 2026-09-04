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
        model.threeDSPresenter = WebKitThreeDSPresenter(host: host) { [weak model] in
            model?.isConfirmingCancel = true
        }
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
    /// Drives the "Cancel Payment?" confirmation. On the model rather than in the
    /// view because a 3DS challenge covers the toolbar, so the request also
    /// arrives from the challenge's own bar.
    @Published var isConfirmingCancel = false

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

    /// Whether to offer the button, decided by Core and asked three questions:
    /// does the session allow the wallet, did the integration configure an
    /// identifier, and does this device have a card.
    ///
    /// Plus a fourth this layer answers for itself: has the session loaded at
    /// all. Core's gate is deliberately permissive about a nil snapshot -- an
    /// absent `wallets` block is "the server had no opinion" and every session
    /// minted before the backend shipped the block reads that way -- but a
    /// snapshot that never arrived is a different thing from one that says
    /// nothing. `load()` swallows a transport failure and a 5xx alike, so
    /// `sessionData` is nil after both, and the request spec needs the
    /// session's own currency and amount. A button that opens onto nothing, or
    /// onto a sheet quoting the wrong money, is worse than no button. The rule
    /// lives here rather than in Core because this is where the render is
    /// decided; Core's semantics are unchanged.
    var showsApplePayButton: Bool {
        guard sessionData != nil else { return false }

        return WalletGate.offersApplePay(
            data: sessionData,
            merchantIdentifier: applePayMerchantIdentifier,
            deviceCanPay: deviceCanPay()
        )
    }

    /// The configured identifier, trimmed, or nil when nothing usable is set.
    ///
    /// Trimmed here because this is the point where the string stops being a
    /// gate input and becomes payload. `WalletGate.offersApplePay` trims before
    /// answering and `WalletToken.applePay` trims before building the body, so
    /// an untrimmed value reaching `PKPaymentRequest` would put an identifier
    /// Apple cannot match beside a submit body carrying the right one: the
    /// sheet never opens and the shopper is told only that Apple Pay could not
    /// be presented.
    private var applePayMerchantIdentifier: String? {
        guard let configured = configuration.applePayMerchantIdentifier else { return nil }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private let sessionToken: String
    private let configuration: Configuration
    private var continuation: CheckedContinuation<PaymentResult, Never>?
    /// Retained so cancelling stops the poll loop. Android gets this for free -
    /// finishing the Activity tears down the viewModelScope - but a bare Task
    /// here would keep polling for the full deadline after the sheet is gone.
    private var paymentTask: Task<Void, Never>?
    /// Ends the sheet once the session can no longer take a payment. Only ever
    /// armed while the form is re-armed after a retryable decline.
    private var sessionDeadlineTask: Task<Void, Never>?
    /// Set once the host controller exists, since the presenter needs somewhere
    /// to attach its web view.
    var threeDSPresenter: (any ThreeDSPresenting)?
    private let walletAuthorizer: (any WalletAuthorizing)?

    /// What the API client sends over.
    ///
    /// Injected for the same reason `PaymentFlowRunner` takes one in Core: the
    /// authorised half of the wallet branch -- the submit body, the poll, a
    /// decline -- is otherwise reachable only by opening a real socket to the
    /// checkout API, so the one path that carries a payment token would have
    /// been first executed on a shopper's device.
    private let transport: any HTTPTransport

    /// Injected so the visibility rule is testable. On the CI simulator the
    /// real one is always false -- a fresh device has an empty Wallet -- so a
    /// model that called PassKit directly would answer "no button" to every
    /// test, and every negative case would pass for the same irrelevant
    /// reason while no positive case could exist at all.
    private let deviceCanPay: @Sendable () -> Bool

    init(
        sessionToken: String,
        claims: SessionClaims,
        configuration: Configuration,
        walletAuthorizer: (any WalletAuthorizing)? = PassKitWalletAuthorizer(),
        deviceCanPay: @escaping @Sendable () -> Bool = {
            PassKitWalletAuthorizer.canMakePayments(networks: ApplePayNetwork.allCases)
        },
        sessionData: SessionData? = nil,
        isPreparing: Bool = true,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.sessionToken = sessionToken
        self.claims = claims
        self.configuration = configuration
        self.walletAuthorizer = walletAuthorizer
        self.deviceCanPay = deviceCanPay
        self.sessionData = sessionData
        self.isPreparing = isPreparing
        self.transport = transport

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
            transport: transport,
            userAgent: "PayCrossSDK-iOS/\(PayCrossAPI.version)"
        )
    }

    /// Fetches the session and acts on what it says.
    ///
    /// A completed session must never render the form: the shopper would pay a
    /// second time, and the new idempotency key gives the backend nothing to
    /// relate the two submissions by.
    func load() async {
        // Started, not awaited. The form must not be gated on WebKit; the value is
        // collected at submit, by which time a healthy WebKit has long answered.
        DeviceInfo.startReadingUserAgent()

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
                applySessionData(response?.data)
                reArm(with: message)
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

    /// Abandons the flow at the shopper's request.
    ///
    /// The server keeps its own record, so a payment cancelled mid-authorization
    /// may still complete; the merchant reconciles that server-side. Android
    /// behaves the same way. What matters is that the shopper is never trapped.
    func cancel() {
        paymentTask?.cancel()
        paymentTask = nil
        finish(.cancelled)
    }


    func pay() {
        guard let card = form.cardData(), !isLoading else { return }

        // Server-driven fields are validated here, not in the form reducer: only
        // visible fields count, and visibility depends on sibling values.
        fieldErrors = FieldGroupLogic.validate(groups: fieldGroups, values: fieldValues)
        guard fieldErrors.isEmpty else { return }

        isLoading = true
        // A payment is in flight again, so the re-armed form's deadline no longer
        // applies; the poll deadline takes over.
        sessionDeadlineTask?.cancel()
        // Clears the CVV from form state the moment it is handed off (Req 3.3.1).
        CardFormReducer.reduce(state: &form, event: .paySubmitted)

        paymentTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.runFlow(with: card)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .finished(let result):
                self.finish(result)
            case .reArmForm(let message):
                self.reArm(with: message)
            }
        }
    }

    /// The wallet's own entry point: `pay()` without the card, plus the sheet.
    ///
    /// Deliberately a sibling rather than a branch inside `pay()`. Two short
    /// methods sharing a tail read better than one guard with a mode in it, and
    /// the card path must not gain a way to be wrong.
    func payWithApplePay() {
        // The same re-entry guard as pay(), without `form.cardData()`: a wallet
        // payment has no card data and would return at that line forever.
        guard !isLoading else { return }

        // Above the validation, so a sheet that could never have opened does
        // not first decorate the form with field errors and then do nothing.
        // Unreachable through the button, which is only offered when the
        // identifier is set.
        guard let merchantIdentifier = applePayMerchantIdentifier,
              let authorizer = walletAuthorizer
        else { return }

        // Before the sheet, not after. Core validates field groups server-side
        // ahead of the wallet branch, so a payment that fails them after Face ID
        // has spent the shopper's authorisation on a rejection they could have
        // been shown first.
        fieldErrors = FieldGroupLogic.validate(groups: fieldGroups, values: fieldValues)
        guard fieldErrors.isEmpty else { return }

        let spec = ApplePayRequestSpec.make(
            claims: claims,
            data: sessionData,
            merchantIdentifier: merchantIdentifier
        )

        isLoading = true
        sessionDeadlineTask?.cancel()

        paymentTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await authorizer.authorize(spec)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .cancelled:
                // The shopper dismissed a sheet. They are still looking at the
                // card form and there is nothing to report.
                self.isLoading = false

            case .failed(let message):
                self.isLoading = false
                CardFormReducer.reduce(state: &self.form, event: .declined(message: message))

            case .authorized(let token):
                await self.submitWallet(token, merchantIdentifier: merchantIdentifier)
            }
        }
    }

    private func submitWallet(_ token: JSONValue, merchantIdentifier: String) async {
        // Unreachable through the button, which is only offered for a non-blank
        // identifier, and fail-closed rather than force-unwrapped: the builder
        // returns nil exactly when the identifier could not be sent, and a body
        // without `merchant_identifier` reads at the edge as a web token and
        // derives the wrong key.
        guard let walletToken = WalletToken.applePay(
            data: token, merchantIdentifier: merchantIdentifier
        ) else {
            isLoading = false
            CardFormReducer.reduce(
                state: &form,
                event: .declined(message: "Apple Pay is not configured for this merchant.")
            )
            return
        }

        let outcome = await runFlow(with: walletToken)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .finished(let result):
            finish(result)
        case .reArmForm(let message):
            reArm(with: message)
        }
    }

    /// Re-arms the form after a decline the shopper may retry.
    ///
    /// One method for all three routes into it — a resumed transaction, a card
    /// payment, a wallet payment — so the session deadline below cannot be
    /// attached to two of them and left off the third.
    func reArm(with message: String) {
        isLoading = false
        CardFormReducer.reduce(state: &form, event: .declined(message: message))
        startSessionDeadline()
    }

    /// Ends the payment once the session can no longer take one.
    ///
    /// A re-armed form has nothing else bounding it: the 480s poll deadline went
    /// with the poll it belonged to. Without this the sheet sits on a live Pay
    /// button long after the session has expired server-side, and the shopper's
    /// next tap can only fail.
    private func startSessionDeadline() {
        sessionDeadlineTask?.cancel()
        // No expiry claim is not the same as an expired session; leave it unbounded
        // rather than guessing a lifetime the server never stated.
        guard let remaining = SessionLifetime.remaining(claims: claims) else { return }

        sessionDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: remaining)
            guard !Task.isCancelled, let self else { return }
            self.finish(SessionLifetime.expired)
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
            browserInfo: await DeviceInfo.browserInfo(),
            // Only visible, non-blank values go on the wire; a hidden field's
            // stale value must not be submitted.
            fieldGroups: FieldGroupLogic.submissionValues(
                groups: fieldGroups, values: fieldValues
            ).nilIfEmpty
        )
        return await runner.run(request)
    }

    /// The card path's twin, and identical after the request is built: submit,
    /// retry-after, poll, terminal. `SubmitCardRequest` has no initialiser that
    /// takes both a card and a wallet token, so the two cannot be confused.
    private func runFlow(with walletToken: WalletToken) async -> FlowOutcome {
        let runner = makeRunner()
        let request = SubmitCardRequest(
            session: sessionToken,
            walletToken: walletToken,
            browserInfo: await DeviceInfo.browserInfo(),
            fieldGroups: FieldGroupLogic.submissionValues(
                groups: fieldGroups, values: fieldValues
            ).nilIfEmpty
        )
        return await runner.run(request)
    }

    private func finish(_ result: PaymentResult) {
        sessionDeadlineTask?.cancel()
        sessionDeadlineTask = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// A fail-closed fallback used when no presenter is attached. Reports failure rather than
/// silently succeeding, so a 3DS session cannot appear to pass without one.
private struct ThreeDSPresenterStub: ThreeDSPresenting {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome { .failed }
    func dismiss() async {}
}

/// Resumes its continuation at most once, so the first of two racing tasks wins
/// and the loser is dropped rather than awaited.
@MainActor
private final class FirstAnswer {
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// Where the real user agent comes from.
///
/// A seam, so a unit test never depends on WebKit launching its helper processes.
typealias UserAgentProvider = @MainActor @Sendable () async -> String?

/// Reads the user agent out of a throwaway web view.
@MainActor
enum WebKitUserAgent {
    static func read() async -> String? {
        let webView = WKWebView(frame: .zero)
        return try? await webView.evaluateJavaScript("navigator.userAgent") as? String
    }
}

/// Collects the device characteristics 3DS v2 requires.
///
/// Every field here except `ip_address` is validated non-blank by
/// `validateBrowserInfo` in the submit-card service, so this is assembled from
/// real values rather than placeholders. `ip_address` itself is omitted: the
/// submit-card Lambda derives it from the request when absent.
@MainActor
enum DeviceInfo {

    /// The real device user agent, which the ACS fingerprints against.
    ///
    /// Android sends `WebSettings.getDefaultUserAgent(context)`; sending the SDK
    /// version string instead is a value the backend accepts and the ACS does
    /// not recognise, which raises the odds of a forced challenge.
    private static var cachedUserAgent: String?

    /// The read in flight, if one is. Held rather than awaited, so the caller that
    /// starts it is not the caller that pays for it.
    private static var reading: Task<String?, Never>?

    /// Replacing the provider discards anything read from the previous one, which
    /// is what a test switching to a stub wants.
    static var userAgentProvider: UserAgentProvider = WebKitUserAgent.read {
        didSet {
            cachedUserAgent = nil
            reading?.cancel()
            reading = nil
        }
    }

    /// Starts reading the real user agent, and returns immediately.
    ///
    /// Nothing awaits this. `evaluateJavaScript` waits on WebKit's helper
    /// processes, which can take tens of seconds to launch on a loaded machine and
    /// need not answer at all — so a sheet that awaited it before fetching its
    /// session showed no form until WebKit was ready, and none at all when WebKit
    /// never came up.
    static func startReadingUserAgent() {
        guard cachedUserAgent == nil, reading == nil else { return }
        reading = Task { await userAgentProvider() }
    }

    /// The real user agent if it has arrived, or arrives within `timeout`; the
    /// fallback otherwise.
    ///
    /// Awaited only where the value is actually consumed, which is the submit body.
    /// A shopper spends many seconds typing a card, so a healthy WebKit has long
    /// since answered and the bound is never reached. The bound is short because by
    /// this point the shopper is waiting on a payment.
    ///
    /// The fallback is not free — `defaultUserAgent` is non-blank and the backend
    /// accepts it, but the ACS does not recognise it, which raises the odds of a
    /// forced challenge — so it is reached only when WebKit is genuinely dead.
    static func userAgent(timeout: Duration = .seconds(2)) async -> String {
        if let cachedUserAgent { return cachedUserAgent }
        startReadingUserAgent()
        guard let reading else { return defaultUserAgent }

        // Not a task group: that waits for every child before it returns, and
        // walking away from a read that may never finish is the whole point.
        let resolved = await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            Task { @MainActor in answer.resume(await reading.value) }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                answer.resume(nil)
            }
        }

        if let resolved { cachedUserAgent = resolved }
        return resolved ?? defaultUserAgent
    }

    static func browserInfo(timeout: Duration = .seconds(2)) async -> BrowserInfo {
        await browserInfo(userAgent: userAgent(timeout: timeout))
    }

    private static func browserInfo(userAgent: String) -> BrowserInfo {

        let bounds = screenBounds()
        let scale = UITraitCollection.current.displayScale
        return BrowserInfo(
            userAgent: userAgent,
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
                        onPay: model.pay,
                        showsApplePayButton: model.showsApplePayButton,
                        onApplePay: { model.payWithApplePay() }
                    )
                }
            }
            .task { await model.load() }
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Never disabled. Authorization runs for up to the full poll
                    // deadline, the sheet is isModalInPresentation so it cannot be
                    // swiped away, and there is no back gesture - gating this on
                    // isLoading left a shopper whose ACS never returns with no way
                    // out at all. Android's back handler is likewise unconditional.
                    Button("Cancel") { model.isConfirmingCancel = true }
                }
            }
            // Same two-step as Android, so a stray tap cannot abandon a payment
            // that is already in flight.
            .alert("Cancel Payment?", isPresented: $model.isConfirmingCancel) {
                Button("Yes, Cancel", role: .destructive, action: model.cancel)
                Button("Continue Payment", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel this payment?")
            }
        }
    }
}
#endif

private extension Dictionary {
    /// Sends nothing rather than an empty object when there is nothing to send.
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
