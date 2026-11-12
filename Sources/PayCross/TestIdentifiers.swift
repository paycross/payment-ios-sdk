#if os(iOS)
import SwiftUI

/// Accessibility identifiers the sheet publishes, for merchant UI tests.
///
/// Each string is the same on Android.
public enum PayCrossTestIdentifiers: String, CaseIterable, Sendable {
    /// The sheet's content, everything under the navigation bar.
    case sheet = "paycross.sheet"

    /// The formatted total. Its accessibility label reads `Total, 25,99 €`.
    case amount = "paycross.amount"

    /// The wallet button: Apple Pay here, Google Pay on Android.
    case walletButton = "paycross.walletButton"

    /// The `Or pay with card` rule between the wallet button and the fields.
    case walletDivider = "paycross.walletDivider"

    /// The stored-card rows and the `Use a new card` row, as one container.
    case savedCards = "paycross.savedCards"

    /// The row that switches from a stored card back to card entry.
    case useNewCard = "paycross.useNewCard"

    case cardNumber = "paycross.cardNumber"
    case expiry = "paycross.expiry"
    case cvv = "paycross.cvv"
    case cardholderName = "paycross.cardholderName"

    /// The detected brand, beside the card number. Empty until a brand is known.
    case brand = "paycross.brand"

    /// The toggle to store a new card, shown only when the session allows saving.
    case saveCard = "paycross.saveCard"

    /// The decline banner. Announced to VoiceOver when it appears.
    case errorBanner = "paycross.errorBanner"

    case payButton = "paycross.payButton"

    /// The spinner shown while the session loads. During a payment it is inside the Pay button.
    case loading = "paycross.loading"

    /// The 3-D Secure challenge, on the view hosting the issuer's page. The fingerprint step has no identifier.
    case threeDS = "paycross.threeDS"

    /// The Cancel button above the challenge.
    case threeDSCancel = "paycross.threeDSCancel"

    /// The Done button above the numeric keypad.
    case keyboardDone = "paycross.keyboardDone"

    /// The sheet's Cancel. It opens the cancel confirmation rather than cancelling the payment.
    case cancel = "paycross.cancel"

    /// The confirmation raised before a payment is abandoned.
    case cancelDialog = "paycross.cancelDialog"

    /// `Yes, Cancel` in the cancel confirmation.
    case cancelConfirm = "paycross.cancelConfirm"

    /// `Continue Payment` in the cancel confirmation.
    case cancelDismiss = "paycross.cancelDismiss"

    /// The confirmation raised before a stored card is deleted.
    case removeDialog = "paycross.removeDialog"

    /// `Remove` in the delete confirmation.
    case removeConfirm = "paycross.removeConfirm"

    /// `Cancel` in the delete confirmation.
    case removeDismiss = "paycross.removeDismiss"

    /// The row for one stored card, by its `uuid` from the session.
    public static func savedCard(_ uuid: String) -> String {
        "paycross.savedCard.\(uuid)"
    }

    /// The trash on one stored card's row.
    public static func savedCardDelete(_ uuid: String) -> String {
        "\(savedCard(uuid)).delete"
    }

    /// One server-driven field, named by its group key and field name from the session.
    ///
    /// Neither part may contain a dot, because the dot separates them and is not escaped.
    public static func field(group: String, name: String) -> String {
        "paycross.field.\(group).\(name)"
    }

    /// The validation message under one server-driven field.
    public static func fieldError(group: String, name: String) -> String {
        "\(field(group: group, name: name)).error"
    }

    /// The toggle for one opt-in field group, shown only when the session marks it opt-in.
    ///
    /// `group` has no dots, as for `field`.
    public static func groupOptIn(group: String) -> String {
        "paycross.group.\(group).optIn"
    }
}

extension View {
    func payCrossIdentifier(_ identifier: PayCrossTestIdentifiers) -> some View {
        accessibilityIdentifier(identifier.rawValue)
    }

    func payCrossContainerIdentifier(_ identifier: PayCrossTestIdentifiers) -> some View {
        accessibilityElement(children: .contain)
            .payCrossIdentifier(identifier)
    }
}
#endif
