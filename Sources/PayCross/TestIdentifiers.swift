#if os(iOS)
import SwiftUI

/// The accessibility identifiers the sheet publishes, for a merchant's UI tests.
///
/// Every one is `paycross.` plus camelCase, and **the same string works on
/// Android**, where the matching Compose `testTag` is published as a resource id.
/// The saved-card identifiers carry the card's `uuid` — the field the session
/// lists it under, so a test can name a specific stored card without reading the
/// screen first.
///
/// Always set, in every build. Android gates its tags on `FLAG_DEBUGGABLE`
/// because a Compose `testTag` published as a resource id is readable by any
/// accessibility service on the device; an iOS `accessibilityIdentifier` is not
/// surfaced to VoiceOver or to other apps, so there is nothing to gate.
///
/// The two dialogs are the exception, and are documented as such in the README:
/// SwiftUI renders `.alert` as a `UIAlertController` the SDK never holds, so
/// only the buttons inside it can be named.
public enum PayCrossTestIdentifiers: String, CaseIterable, Sendable {

    /// The sheet's content, everything under the navigation bar.
    case sheet = "paycross.sheet"

    /// The formatted total. Its accessibility label reads `Total, 25,99 €`.
    case amount = "paycross.amount"

    /// The Apple Pay button. Named for the wallet rather than for Apple so the
    /// string is the one Android uses for Google Pay.
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

    /// The toggle offering to store the card. Present only when the session
    /// allows saving and a new card is being entered.
    case saveCard = "paycross.saveCard"

    /// The decline banner. Announced to VoiceOver when it appears.
    case errorBanner = "paycross.errorBanner"

    case payButton = "paycross.payButton"

    /// The spinner shown while the session is being fetched. While a payment is
    /// in flight the spinner is inside the Pay button instead, which keeps its
    /// own identifier, so this is the initial load only.
    case loading = "paycross.loading"

    /// The 3-D Secure challenge, on the view hosting the issuer's page. The
    /// invisible fingerprint step carries no identifier: there is nothing to
    /// address, and a test that waited for one would hang.
    case threeDS = "paycross.threeDS"

    /// The Cancel button above the challenge.
    case threeDSCancel = "paycross.threeDSCancel"

    /// The Done button above the numeric keypad.
    case keyboardDone = "paycross.keyboardDone"

    /// `Yes, Cancel` in the cancel confirmation.
    case cancelConfirm = "paycross.cancelConfirm"

    /// `Continue Payment` in the cancel confirmation.
    case cancelDismiss = "paycross.cancelDismiss"

    /// `Remove` in the delete confirmation.
    case removeConfirm = "paycross.removeConfirm"

    /// `Cancel` in the delete confirmation.
    case removeDismiss = "paycross.removeDismiss"

    /// One stored card's row. `uuid` is the card's `uuid` from the session.
    public static func savedCard(_ uuid: String) -> String {
        "paycross.savedCard.\(uuid)"
    }

    /// The trash on one stored card's row.
    public static func savedCardDelete(_ uuid: String) -> String {
        "\(savedCard(uuid)).delete"
    }

    /// One server-driven field. Both parts come from the session's
    /// `field_groups`: the group's key and the field's name.
    public static func field(group: String, name: String) -> String {
        "paycross.field.\(group).\(name)"
    }

    /// The validation message under one server-driven field.
    public static func fieldError(group: String, name: String) -> String {
        "\(field(group: group, name: name)).error"
    }
}

extension View {
    /// Reads better than `accessibilityIdentifier(_.rawValue)` at two dozen call
    /// sites, and keeps the raw strings in one file.
    func payCrossIdentifier(_ identifier: PayCrossTestIdentifiers) -> some View {
        accessibilityIdentifier(identifier.rawValue)
    }
}
#endif
