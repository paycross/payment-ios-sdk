#if os(iOS)
import Foundation
import PassKit
import PayCrossCore

/// Presents Apple's payment sheet and answers with the token it produced.
///
/// The only file in this SDK that talks to PassKit's payment machinery.
/// `UI/ApplePayButtonView.swift` imports the framework too, but only to name
/// Apple's button. Every decision around this one -- whether to offer the
/// button, what to ask Apple for, what to put on the wire -- lives in
/// `PayCrossCore` and is proved on Linux. What is left here is presentation and
/// one mapping.
///
/// The continuation discipline is the one `WebKitThreeDSPresenter` documents
/// and for the same reason: `PKPaymentAuthorizationController` reports the
/// authorisation and the dismissal through two separate delegate callbacks, so
/// an outcome is recorded by the first and delivered by the second. Resuming in
/// the first would leave a sheet on screen over a finished flow; not resuming
/// in the second would hang the payment forever if the shopper swipes the sheet
/// away.
///
/// The delivery happens in `didFinish` itself rather than in `dismiss`'s
/// completion block. That completion is not promised to run when there is
/// nothing to dismiss -- a controller already gone, a presenting window torn
/// down -- and this path has no timeout, so waiting on it can leave the form
/// locked on `isLoading` for the life of the sheet. Dismissal is therefore
/// asked for and not waited on. Nothing that matters is given up: the next
/// thing that happens is a network submit, so the merchant's UI has no reason
/// to wait for Apple's sheet to finish animating away.
///
/// `@MainActor`, like that class (`ThreeDSWebViewController.swift:193-194`),
/// and for a reason the compiler will not catch: `authorize` witnesses a
/// nonisolated `async` protocol requirement, so without the annotation it hops
/// off the main actor and presents a UIKit sheet from a cooperative-pool
/// thread, while PassKit writes the three properties below from the main
/// queue. A `@MainActor` class is `Sendable` for free and its mutable state is
/// protected by the actor, which is why there is no `@unchecked Sendable` here.
/// Adding one would silence the compiler rather than make the race go away.
@MainActor
final class PassKitWalletAuthorizer: NSObject, WalletAuthorizing {

    private var continuation: CheckedContinuation<WalletAuthorizationOutcome, Never>?
    private var outcome: WalletAuthorizationOutcome = .cancelled
    private var controller: PKPaymentAuthorizationController?

    /// Whether this device has a card it could pay one of these networks with.
    ///
    /// `canMakePayments(usingNetworks:)`, not the bare `canMakePayments()`: the
    /// bare one answers "this device supports Apple Pay", which is true of a
    /// phone with an empty Wallet, and a button that opens onto "no cards"
    /// is worse than no button.
    ///
    /// Deliberately `nonisolated`: it reads no state, and the model calls it
    /// from a property getter.
    nonisolated static func canMakePayments(networks: [ApplePayNetwork]) -> Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks.map(paymentNetwork))
    }

    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome {
        // A second sheet on the same instance would overwrite the first
        // continuation, and its caller would then wait forever with nothing to
        // read but a SWIFT TASK CONTINUATION MISUSE line in the log. It would
        // also drop a controller that is still on screen. The payment sheet's
        // own `guard !isLoading` serialises this today, but that guard lives in
        // another file, and a second caller is the kind of thing a plugin
        // bridge adds without noticing.
        guard continuation == nil else {
            return .failed("An Apple Pay sheet is already open.")
        }

        let controller = PKPaymentAuthorizationController(paymentRequest: Self.makeRequest(spec))
        controller.delegate = self
        self.controller = controller
        outcome = .cancelled

        let presented = await controller.present()
        guard presented else {
            self.controller = nil
            return .failed(Self.presentationFailureMessage(for: spec))
        }

        return await awaitDelegateOutcome()
    }

    /// What the SDK says when Apple refuses to open the sheet.
    ///
    /// Named, because `present()` answers a bare false and answers it almost
    /// exclusively for a misconfigured request: an identifier that is not in
    /// the app's Apple Pay entitlement, an unsupported country or currency, an
    /// empty network list. The shopper can pay by card either way, so the
    /// sentence hardly matters to them; the merchant integrating the SDK has
    /// nothing else to go on, and this identifier is not a secret.
    ///
    /// A separate function because the failure it describes cannot be reached
    /// from a test -- `present()` neither succeeds nor returns on a simulator
    /// with no entitlement -- and a message that names nothing is exactly the
    /// regression worth pinning.
    static func presentationFailureMessage(for spec: ApplePayRequestSpec) -> String {
        "Apple Pay could not be presented for \(spec.merchantIdentifier). "
            + "Check the app's Apple Pay entitlement and the merchant identifier."
    }

    /// Everything the sheet is asked for, as a pure function of the spec.
    ///
    /// Separated from `authorize` so it can be asserted without a sheet. It is
    /// the only place the SDK translates its own vocabulary into Apple's, and a
    /// silent mistake here -- a dropped capability, a network list that does
    /// not match what the device check asked about -- produces a sheet that
    /// refuses to present, for every merchant, with nothing to grep for.
    static func makeRequest(_ spec: ApplePayRequestSpec) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = spec.merchantIdentifier
        request.countryCode = spec.countryCode
        request.currencyCode = spec.currencyCode
        request.supportedNetworks = spec.supportedNetworks.map(paymentNetwork)
        request.merchantCapabilities = spec.capabilities.reduce(into: []) { $0.insert(capability($1)) }
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: spec.summaryItemLabel,
                amount: NSDecimalNumber(decimal: spec.amountMajorUnits),
                type: .final
            )
        ]
        return request
    }

    /// Installs the continuation the delegate resumes, and does nothing else.
    ///
    /// Split out of `authorize` to be reachable from a test. A simulator has no
    /// Apple Pay entitlement, so `present()` there always answers false and
    /// `authorize` returns before it reaches this line -- which would leave the
    /// resume discipline, the one thing in this file that can hang a payment,
    /// executed by nothing but a real device.
    func awaitDelegateOutcome() async -> WalletAuthorizationOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Whether a caller is waiting on the delegate.
    ///
    /// Read-only, and here so a test can tell the continuation is installed
    /// before driving the delegate. Resuming one that is not there yet would
    /// hang the test rather than fail it.
    var isAwaitingOutcome: Bool { continuation != nil }

    private func resume(_ value: WalletAuthorizationOutcome) {
        // Cleared before resuming, so a second delegate callback cannot
        // resume a continuation that is already gone. The same shape as
        // WebKitThreeDSPresenter.resolve, and for the same reason.
        guard let continuation else { return }
        self.continuation = nil
        self.controller = nil
        continuation.resume(returning: value)
    }

    /// `nonisolated` because `canMakePayments` above is, and a `@MainActor`
    /// class makes its static members `@MainActor` too. Swift 6 rejects passing
    /// an isolated function as a plain `(ApplePayNetwork) -> PKPaymentNetwork`
    /// to `map`. The mapping reads no state, so dropping the isolation is
    /// honest rather than a workaround.
    nonisolated private static func paymentNetwork(_ network: ApplePayNetwork) -> PKPaymentNetwork {
        switch network {
        case .visa: .visa
        case .mastercard: .masterCard
        case .amex: .amex
        case .discover: .discover
        case .jcb: .JCB
        }
    }

    private static func capability(_ capability: ApplePayCapability) -> PKMerchantCapability {
        switch capability {
        case .threeDSecure: .capability3DS
        case .credit: .capabilityCredit
        case .debit: .capabilityDebit
        }
    }

    /// The token, shaped exactly as the web checkout posts it.
    ///
    /// `paymentData` at the top level is not a preference: the edge looks for
    /// `data.paymentData` and falls back to `data.token.paymentData`, and
    /// anything else is a 400 that names nothing.
    ///
    /// `paymentMethod` is read too, and dropping it would be worse than
    /// untidy. The edge lifts three fields out of it
    /// (`payment-submit-card/internal/handler/wallet.go:143-172`): `network`
    /// becomes the card brand the vault seals into the wallet credential and
    /// the provider forwards to the gateway, `displayName` becomes the masked
    /// digits, and `type` becomes the funding type the back office shows. Only
    /// `transactionIdentifier` is carried for fidelity alone.
    private static func tokenJSON(_ token: PKPaymentToken) -> JSONValue? {
        guard let paymentData = try? JSONDecoder().decode(JSONValue.self, from: token.paymentData) else {
            return nil
        }

        var method: [String: JSONValue] = ["type": .string(describe(token.paymentMethod.type))]
        if let displayName = token.paymentMethod.displayName {
            method["displayName"] = .string(displayName)
        }
        if let network = token.paymentMethod.network {
            method["network"] = .string(network.rawValue)
        }

        return .object([
            "paymentData": paymentData,
            "paymentMethod": .object(method),
            "transactionIdentifier": .string(token.transactionIdentifier)
        ])
    }

    private static func describe(_ type: PKPaymentMethodType) -> String {
        switch type {
        case .debit: "debit"
        case .credit: "credit"
        case .prepaid: "prepaid"
        case .store: "store"
        case .eMoney: "eMoney"
        default: "unknown"
        }
    }
}

extension PassKitWalletAuthorizer: PKPaymentAuthorizationControllerDelegate {

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // Apple wants the result of this sheet, not the result of the payment.
        // Reporting .success here means "the token is well formed and we have
        // it"; the payment itself is submitted afterwards and can still
        // decline, which the card form already knows how to show. Holding the
        // sheet open until the server answers would put a PassKit spinner in
        // front of a flow that can take minutes.
        if let token = Self.tokenJSON(payment.token) {
            outcome = .authorized(token)
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        } else {
            outcome = .failed("Apple Pay returned a token this SDK could not read.")
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        // The only place the continuation is resumed. Reached after an
        // authorisation, after a cancel, and after a dismissal -- which is why
        // `outcome` defaults to .cancelled at the top of every authorize call.
        // The dismissal is asked for and not waited on: resuming from its
        // completion block would make the whole payment conditional on a
        // callback Apple does not promise to run, with no timeout anywhere on
        // the path, and the symptom would be a form locked on `isLoading` until
        // the shopper cancels. It would also put the resume inside an
        // unisolated `@Sendable` closure, needing an `assumeIsolated` whose
        // failure mode in a shipped payments SDK is a trap mid-payment.
        controller.dismiss(completion: nil)
        resume(outcome)
    }
}
#endif
