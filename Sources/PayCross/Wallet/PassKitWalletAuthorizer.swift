#if os(iOS)
import Foundation
import PassKit
import PayCrossCore

// PassKit reports the authorisation and the dismissal through two delegate callbacks, so
// the continuation is resumed only by the second.
// Authorize witnesses a nonisolated async requirement; without @MainActor it would present
// UIKit from a background thread while PassKit writes the state from the main queue.
@MainActor
final class PassKitWalletAuthorizer: NSObject, WalletAuthorizing {

    private var continuation: CheckedContinuation<WalletAuthorizationOutcome, Never>?
    private var outcome: WalletAuthorizationOutcome = .cancelled
    private var controller: PKPaymentAuthorizationController?

    // The bare canMakePayments() is true for a device with an empty Wallet.
    // Nonisolated, because the model reads it from a property getter.
    nonisolated static func canMakePayments(networks: [ApplePayNetwork]) -> Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks.map(paymentNetwork))
    }

    func authorize(_ spec: ApplePayRequestSpec) async -> WalletAuthorizationOutcome {
        // A second sheet would overwrite the continuation, and its caller would wait forever.
        guard continuation == nil else {
            return .failed(L(
                "paycross_error_apple_pay_busy",
                "An Apple Pay sheet is already open."
            ))
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

    // present() returns a bare false for a misconfigured request, so this message is the only clue.
    static func presentationFailureMessage(for spec: ApplePayRequestSpec) -> String {
        L(
            "paycross_error_apple_pay_presentation",
            "Apple Pay could not be presented for %@. "
                + "Check the app's Apple Pay entitlement and the merchant identifier.",
            spec.merchantIdentifier
        )
    }

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

    // Repeats authorize's guard, since two callers can both pass it and suspend on present()
    // before either arrives here.
    func awaitDelegateOutcome() async -> WalletAuthorizationOutcome {
        guard continuation == nil else {
            return .failed(L(
                "paycross_error_apple_pay_busy",
                "An Apple Pay sheet is already open."
            ))
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    var isAwaitingOutcome: Bool { continuation != nil }

    private func resume(_ value: WalletAuthorizationOutcome) {
        // Cleared before resuming, so a second delegate callback cannot resume it again.
        guard let continuation else { return }
        self.continuation = nil
        self.controller = nil
        continuation.resume(returning: value)
    }

    // Nonisolated, because Swift 6 rejects passing an isolated function to map as a plain
    // (ApplePayNetwork) -> PKPaymentNetwork.
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

    // The server reads paymentData from the top level and paymentMethod for the card brand,
    // the masked digits and the funding type.
    static func tokenJSON(_ token: PKPaymentToken) -> JSONValue? {
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
        // Success means the token is well formed; the payment is submitted afterwards and can still decline.
        if let token = Self.tokenJSON(payment.token) {
            outcome = .authorized(token)
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        } else {
            outcome = .failed(L(
                "paycross_error_apple_pay_token",
                "Apple Pay returned a token this SDK could not read."
            ))
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        // Resumed only here, after an authorisation, a cancel or a dismissal.
        // The dismissal is not waited on: its completion is not promised to run, and the form
        // would stay locked on isLoading.
        controller.dismiss(completion: nil)
        resume(outcome)
    }
}
#endif
