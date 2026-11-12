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
/// case .succeeded(let id, _, let amount, let savedCardToken): …
/// case .failed(_, let recovery) where recovery.isRetryable: …
/// case .failed: …
/// case .pending(let transactionID, _): // Reconcile before charging again.
/// case .cancelled(let transactionID): …
/// }
/// ```
///
/// Nothing throws: a decline is returned as `.failed`, not as a Swift `Error`.
@MainActor
public final class PaymentSheet {
    private let sessionToken: String

    /// Creates a sheet for a session token from your server. The session decides
    /// the saved cards, field groups and whether saving is offered.
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

        SheetLanguage.install(LocaleResolution.resolve(
            override: configuration.locale,
            device: DeviceLanguages.preferred()
        ))

        let model = PaymentSheetModel(
            sessionToken: sessionToken,
            claims: claims,
            configuration: configuration
        )

        let host = PaymentHostController(model: model)
        host.isModalInPresentation = true
        model.threeDSPresenter = WebKitThreeDSPresenter(
            host: host,
            surfaceColor: model.appearance.uiColor(\.surface)
        ) { [weak model] in
            model?.isConfirmingCancel = true
        }
        presenter.present(host, animated: true)

        let result = await model.awaitResult()
        await host.dismissSelf()
        SheetLanguage.reset()
        return result
    }
}

@MainActor
final class PaymentHostController: UIHostingController<PaymentSheetView> {
    init(model: PaymentSheetModel) {
        super.init(rootView: PaymentSheetView(model: model))
        overrideUserInterfaceStyle = model.appearance.userInterfaceStyle
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

@MainActor
final class PaymentSheetModel: ObservableObject {
    @Published var form: CardFormState
    @Published private(set) var isLoading = false
    @Published private(set) var isPreparing = true
    @Published private(set) var sessionData: SessionData?
    @Published private(set) var appearance: AppearanceStyle
    private var warnedAppearance: ResolvedAppearance?
    @Published private(set) var formattingLocale: Locale = SheetLanguage.locale
    @Published private(set) var languageTag: String = SheetLanguage.tag
    @Published var fieldValues: [String: [String: String]] = [:]
    @Published var optedInGroups: Set<String> = [] {
        didSet {
            guard optedInGroups != oldValue else { return }
            let active = Set(activeFieldGroups.map(\.key))
            fieldErrors.removeAll { !active.contains($0.groupKey) }
        }
    }
    @Published private(set) var fieldErrors: [FieldGroupError] = []
    @Published var isConfirmingCancel = false
    @Published var cardPendingRemoval: SavedCard?

    let claims: SessionClaims

    var allowsCardRemoval: Bool {
        sessionData?.allowsSavedCardRemoval ?? false
    }

    var allowsSavingCard: Bool {
        sessionData?.allowsSavingCard ?? false
    }

    var fieldGroups: [FieldGroup] {
        sessionData?.fieldGroups ?? []
    }

    var activeFieldGroups: [FieldGroup] {
        FieldGroupLogic.activeGroups(fieldGroups, optedIn: optedInGroups)
    }

    // sessionData stays nil when load() fails, and the button needs the session's currency and amount.
    var showsApplePayButton: Bool {
        guard sessionData != nil else { return false }

        return WalletGate.offersApplePay(
            data: sessionData,
            merchantIdentifier: applePayMerchantIdentifier,
            deviceCanPay: deviceCanPay()
        )
    }

    // Trimmed here, where the string becomes payload, so the gate and the request agree.
    private var applePayMerchantIdentifier: String? {
        guard let configured = configuration.applePayMerchantIdentifier else { return nil }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private let sessionToken: String
    private let configuration: Configuration
    private var continuation: CheckedContinuation<PaymentResult, Never>?
    private var paymentTask: Task<Void, Never>?
    private var sessionDeadlineTask: Task<Void, Never>?
    private(set) var removalTask: Task<Void, Never>?
    private(set) var lastTransactionID: String?
    var threeDSPresenter: (any ThreeDSPresenting)?
    private let walletAuthorizer: (any WalletAuthorizing)?

    private let transport: any HTTPTransport

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
        self.appearance = AppearanceStyle(
            resolved: AppearanceResolver.resolve(
                appearance: configuration.appearance,
                serverBrandColor: sessionData?.branding?.brandColor
            )
        )

        var initial = CardFormState(source: .newCard)
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

        warnAboutContrast()
    }

    var amount: Amount { claims.amount }

    private func makeClient() -> PayCrossAPIClient {
        PayCrossAPIClient(
            baseURL: configuration.environment.baseURL,
            transport: transport,
            userAgent: "PayCrossSDK-iOS/\(PayCrossAPI.version)"
        )
    }

    func load() async {
        // The form must not wait on WebKit; the user agent is read at submit.
        DeviceInfo.startReadingUserAgent()

        let response = try? await makeClient()
            .session(id: claims.sessionID, sessionToken: sessionToken)

        // Ahead of the switch on purpose: the `.resume` branch builds a runner,
        // and a runner is handed its sentences at construction.
        installLanguage(session: response?.data?.locale)

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

    private func installLanguage(session sessionLocale: String?) {
        SheetLanguage.install(LocaleResolution.resolve(
            override: configuration.locale,
            session: sessionLocale,
            device: DeviceLanguages.preferred()
        ))
        formattingLocale = SheetLanguage.locale
        languageTag = SheetLanguage.tag
    }

    var flowMessages: FlowMessages {
        FlowMessages(
            paymentFailed: L("paycross_error_payment_failed", "Payment failed. Please try again."),
            networkError: L("paycross_error_network", "Network error. Please try again."),
            submissionFailed: L("paycross_error_submission_failed", "Payment submission failed"),
            fieldRequired: L("paycross_field_required", "%@ is required"),
            fieldInvalid: L("paycross_field_invalid", "%@ is invalid"),
            fieldTooLong: L(
                "paycross_field_max_length", "%@ must be %@ characters or fewer"
            )
        )
    }

    private func applySessionData(_ data: SessionData?) {
        guard let data else { return }
        sessionData = data
        appearance = AppearanceStyle(
            resolved: AppearanceResolver.resolve(
                appearance: configuration.appearance,
                serverBrandColor: data.branding?.brandColor
            )
        )
        warnAboutContrast()
        fieldValues = FieldGroupLogic.initialValues(data.fieldGroups ?? [])
        // A session re-read must not carry over a group the shopper opted into.
        optedInGroups = []
        form.savedCards = data.savedCards?.map(\.presentable) ?? []

        // A preselected saved card still needs its CVV before it can be charged.
        if data.preselectsSavedCard, let first = form.savedCards.first {
            CardFormReducer.reduce(state: &form, event: .sourceSelected(.saved(first)))
        }
    }

    private func warnAboutContrast() {
        #if DEBUG
        guard warnedAppearance != appearance.resolved else { return }
        warnedAppearance = appearance.resolved
        for warning in AppearanceResolver.contrastWarnings(for: appearance.resolved) {
            print("PayCrossAppearance: \(warning)")
        }
        #endif
    }

    func requestRemoval(of card: SavedCard) {
        cardPendingRemoval = card
    }

    func cancelRemoval() {
        cardPendingRemoval = nil
    }

    func confirmRemoval() {
        guard let card = cardPendingRemoval else { return }
        cardPendingRemoval = nil
        removeSavedCard(card)
    }

    func removeSavedCard(_ card: SavedCard) {
        // A card is not removed while a payment that may charge it is running.
        guard !isLoading else { return }

        removalTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.makeClient().deleteSavedCard(
                    uuid: card.id, sessionToken: self.sessionToken
                )
                self.drop(card)
            } catch PayCrossError.notFound {
                // notFound means the card is already gone, so the row is dropped without an error.
                self.drop(card)
            } catch PayCrossError.sessionExpired {
                // A retry cannot succeed on an expired session.
                self.show(L(
                    "paycross_session_expired",
                    "This payment session has expired. Start again."
                ))
            } catch {
                self.show(L(
                    "paycross_remove_card_failed",
                    "Could not remove the card. Try again."
                ))
            }
        }
    }

    private func drop(_ card: SavedCard) {
        CardFormReducer.reduce(state: &form, event: .savedCardRemoved(uuid: card.id))
    }

    private func show(_ message: String) {
        // Not a reducer event, which would clear the CVV the shopper still needs.
        form.inlineError = message
    }

    func awaitResult() async -> PaymentResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        paymentTask?.cancel()
        paymentTask = nil
        finish(.cancelled(transactionID: lastTransactionID))
    }

    func pay() {
        guard let card = form.cardData(), !isLoading else { return }

        // Validated here, not in the form reducer, because visibility depends on sibling values.
        fieldErrors = FieldGroupLogic.validate(
            groups: activeFieldGroups, values: fieldValues,
            messages: flowMessages, language: languageTag
        )
        guard fieldErrors.isEmpty else { return }

        isLoading = true
        sessionDeadlineTask?.cancel()
        // The CVV is cleared from form state on hand-off (Req 3.3.1).
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

    func payWithApplePay() {
        // A wallet payment has no card data, so pay()'s guard cannot be used.
        guard !isLoading else { return }

        // Checked before validation, so no field errors appear when no sheet can open.
        guard let merchantIdentifier = applePayMerchantIdentifier,
              let authorizer = walletAuthorizer
        else { return }

        // Validated before the wallet sheet, so a rejection is shown before Face ID is asked.
        fieldErrors = FieldGroupLogic.validate(
            groups: activeFieldGroups, values: fieldValues,
            messages: flowMessages, language: languageTag
        )
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
                self.isLoading = false

            case .failed(let message):
                self.isLoading = false
                CardFormReducer.reduce(
                    state: &self.form,
                    event: .walletDeclined(message: message)
                )

            case .authorized(let token):
                await self.submitWallet(token, merchantIdentifier: merchantIdentifier)
            }
        }
    }

    private func submitWallet(_ token: JSONValue, merchantIdentifier: String) async {
        // Fails closed rather than force-unwrapping, because a body without `merchant_identifier` reads as a web token.
        guard let walletToken = WalletToken.applePay(
            data: token, merchantIdentifier: merchantIdentifier
        ) else {
            isLoading = false
            CardFormReducer.reduce(
                state: &form,
                event: .walletDeclined(
                    message: L(
                        "paycross_apple_pay_not_configured",
                        "Apple Pay is not configured for this merchant."
                    )
                )
            )
            return
        }

        let outcome = await runFlow(with: walletToken)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .finished(let result):
            finish(result)
        case .reArmForm(let message):
            reArmAfterWalletDecline(with: message)
        }
    }

    func reArm(with message: String) {
        reArm(showing: .declined(message: message))
    }

    func reArmAfterWalletDecline(with message: String) {
        reArm(showing: .walletDeclined(message: message))
    }

    private func reArm(showing event: CardFormEvent) {
        isLoading = false
        CardFormReducer.reduce(state: &form, event: event)
        startSessionDeadline()
    }

    private func startSessionDeadline() {
        sessionDeadlineTask?.cancel()
        // Without an expiry claim the session is unbounded, not expired.
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
            // A missing presenter reports .failed, so an unanswered challenge is not shown as answered.
            presenter: threeDSPresenter ?? ThreeDSPresenterStub(),
            claims: claims,
            messages: flowMessages,
            onTransactionID: { [weak self] id in
                await MainActor.run { self?.lastTransactionID = id }
            }
        )
    }

    private func runFlow(with card: CardData) async -> FlowOutcome {
        let runner = makeRunner()
        let request = SubmitCardRequest(
            session: sessionToken,
            card: card,
            browserInfo: await DeviceInfo.browserInfo(),
            // A hidden field's stale value must not be submitted.
            fieldGroups: FieldGroupLogic.submissionValues(
                groups: activeFieldGroups, values: fieldValues
            ).nilIfEmpty
        )
        return await runner.run(request)
    }

    private func runFlow(with walletToken: WalletToken) async -> FlowOutcome {
        let runner = makeRunner()
        let request = SubmitCardRequest(
            session: sessionToken,
            walletToken: walletToken,
            browserInfo: await DeviceInfo.browserInfo(),
            fieldGroups: FieldGroupLogic.submissionValues(
                groups: activeFieldGroups, values: fieldValues
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

private struct ThreeDSPresenterStub: ThreeDSPresenting {
    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome { .failed }
    func dismiss() async {}
}

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

typealias UserAgentProvider = @MainActor @Sendable () async -> String?

typealias BoundedWait = @MainActor @Sendable (Duration) async -> Void

@MainActor
enum WebKitUserAgent {
    static func read() async -> String? {
        let webView = WKWebView(frame: .zero)
        return try? await webView.evaluateJavaScript("navigator.userAgent") as? String
    }
}

@MainActor
enum DeviceInfo {
    private static var cachedUserAgent: String?

    private static var reading: Task<String?, Never>?

    static var userAgentProvider: UserAgentProvider = WebKitUserAgent.read {
        didSet {
            cachedUserAgent = nil
            reading?.cancel()
            reading = nil
        }
    }

    static var boundedWait: BoundedWait = { duration in
        try? await Task.sleep(for: duration)
    }

    static func startReadingUserAgent() {
        guard cachedUserAgent == nil, reading == nil else { return }
        reading = Task { await userAgentProvider() }
    }

    static func userAgent(timeout: Duration = .seconds(2)) async -> String {
        if let cachedUserAgent { return cachedUserAgent }
        startReadingUserAgent()
        guard let reading else { return defaultUserAgent }

        // Not a task group, which would wait for a read that may never finish.
        let resolved = await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            Task { @MainActor in answer.resume(await reading.value) }
            Task { @MainActor in
                await boundedWait(timeout)
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
            // 3DS wants pixels, not points.
            screenWidth: Int(bounds.width * scale),
            screenHeight: Int(bounds.height * scale),
            timezoneOffset: BrowserInfo.timezoneOffsetMinutes(),
            // The backend rejects extension subtags, so the BCP-47 tag is clamped.
            language: BrowserInfo.clampedLanguageTag(Locale.current.identifier(.bcp47))
        )
    }

    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) PayCrossSDK-iOS/\(PayCrossAPI.version)"

    private static func screenBounds() -> CGRect {
        // UIScreen.main is deprecated from iOS 16, so the active scene is read.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
}

struct PaymentSheetView: View {
    @ObservedObject var model: PaymentSheetModel
    @AccessibilityFocusState private var cancelFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if model.isPreparing {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .payCrossIdentifier(.loading)
                } else {
                    CardFormView(
                        state: $model.form,
                        amount: model.amount,
                        allowsSaving: model.allowsSavingCard,
                        allowsCardRemoval: model.allowsCardRemoval,
                        isLoading: model.isLoading,
                        fieldGroups: model.fieldGroups,
                        fieldValues: $model.fieldValues,
                        optedInGroups: $model.optedInGroups,
                        fieldErrors: model.fieldErrors,
                        language: model.languageTag,
                        onPay: model.pay,
                        showsApplePayButton: model.showsApplePayButton,
                        onApplePay: { model.payWithApplePay() },
                        onRemoveRequested: { model.requestRemoval(of: $0) }
                    )
                }
            }
            .payCrossContainerIdentifier(.sheet)
            .task { await model.load() }
            // SwiftUI's formatting must follow the locale the amount is formatted in.
            .environment(\.locale, model.formattingLocale)
            .payCrossTint(model.appearance.color(\.brand))
            .payCrossSheetChrome(model.appearance)
            .navigationTitle(L("paycross_payment", "Payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Never disabled, so a shopper whose challenge never returns can still cancel.
                    Button(L("paycross_cancel", "Cancel")) { model.isConfirmingCancel = true }
                        .payCrossIdentifier(PayCrossTestIdentifiers.cancel)
                        .accessibilityFocused($cancelFocused)
                }
            }
            // Not an `.alert`, because SwiftUI does not carry button identifiers onto `UIAlertAction`.
            .overlay { confirmation }
            .onChange(of: model.isConfirmingCancel) { isConfirming in
                if !isConfirming { cancelFocused = true }
            }
        }
        // The 3-D Secure challenge is not capped by this type scale; its page sizes its own text.
        .payCrossTypeScale(model.appearance)
    }

    @ViewBuilder
    private var confirmation: some View {
        if model.isConfirmingCancel {
            // Two steps, so a stray tap cannot abandon a payment in flight.
            ConfirmationDialog(
                identifier: PayCrossTestIdentifiers.cancelDialog,
                title: L("paycross_cancel_payment_title", "Cancel Payment?"),
                message: L(
                    "paycross_cancel_payment_message",
                    "Are you sure you want to cancel this payment?"
                ),
                confirm: .init(
                    title: L("paycross_cancel_payment_yes", "Yes, Cancel"),
                    identifier: PayCrossTestIdentifiers.cancelConfirm,
                    action: model.cancel
                ),
                dismiss: .init(
                    title: L("paycross_cancel_payment_continue", "Continue Payment"),
                    identifier: PayCrossTestIdentifiers.cancelDismiss,
                    action: { model.isConfirmingCancel = false }
                )
            )
        } else if let card = model.cardPendingRemoval {
            // Deleting a card is not undoable, and the trash sits next to the row that selects it.
            ConfirmationDialog(
                identifier: PayCrossTestIdentifiers.removeDialog,
                title: L("paycross_remove_card_title", "Remove this card?"),
                message: L(
                    "paycross_remove_card_message",
                    "%@ will no longer be offered for future payments.",
                    card.rowTitle
                ),
                confirm: .init(
                    title: L("paycross_remove_card_confirm", "Remove"),
                    identifier: PayCrossTestIdentifiers.removeConfirm,
                    action: model.confirmRemoval
                ),
                dismiss: .init(
                    title: L("paycross_cancel", "Cancel"),
                    identifier: PayCrossTestIdentifiers.removeDismiss,
                    action: model.cancelRemoval
                )
            )
        }
    }
}
#endif

private extension Dictionary {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
