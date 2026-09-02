#if os(iOS)
import Foundation
import PassKit
import PayCrossCore

/// Presents Apple's payment sheet and answers with the token it produced.
///
/// The only file in this SDK that imports PassKit, which is why every decision
/// around it -- whether to offer the button, what to ask Apple for, what to put
/// on the wire -- lives in `PayCrossCore` and is proved on Linux. What is left
/// here is presentation and one mapping, and both are things only a device can
/// exercise.
///
/// The continuation discipline is the one `WebKitThreeDSPresenter` documents
/// and for the same reason: `PKPaymentAuthorizationController` reports the
/// authorisation and the dismissal through two separate delegate callbacks, so
/// an outcome is recorded by the first and delivered by the second. Resuming in
/// the first would leave a sheet on screen over a finished flow; not resuming
/// in the second would hang the payment forever if the shopper swipes the sheet
/// away.
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
        let request = PKPaymentRequest()
        request.merchantIdentifier = spec.merchantIdentifier
        request.countryCode = spec.countryCode
        request.currencyCode = spec.currencyCode
        request.supportedNetworks = spec.supportedNetworks.map(Self.paymentNetwork)
        request.merchantCapabilities = spec.capabilities.reduce(into: []) { $0.insert(Self.capability($1)) }
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: spec.summaryItemLabel,
                amount: NSDecimalNumber(decimal: spec.amountMajorUnits),
                type: .final
            )
        ]

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        outcome = .cancelled

        let presented = await controller.present()
        guard presented else {
            self.controller = nil
            return .failed("Apple Pay could not be presented.")
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

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
        // `dismiss`'s completion is a plain `@Sendable` closure with no
        // isolation of its own, and PassKit runs it on the main queue. The
        // assumption is asserted rather than assumed away: `assumeIsolated`
        // traps if it is ever called anywhere else, whereas `@unchecked
        // Sendable` on this class would hide exactly the race the isolation
        // exists to prevent.
        controller.dismiss {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.resume(self.outcome)
            }
        }
    }
}
#endif
