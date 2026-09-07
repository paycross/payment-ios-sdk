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
/// Cases are added as the sheet grows elements worth reaching. Switching over
/// this exhaustively is not what it is for; read the case you want.
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

    /// The sheet's own Cancel, which opens the cancel confirmation rather than
    /// cancelling anything. The confirmation's buttons are below.
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
    ///
    /// **Both must be free of dots.** The dot is the separator, and nothing
    /// escapes it, so `("a.b", "c")` and `("a", "b.c")` would answer to the same
    /// string. That is deliberate rather than overlooked: Android joins these
    /// the same way, and one identifier has to name one field on both platforms,
    /// so an escaping rule would have to be invented twice and kept identical.
    /// Neither half is shopper input — they are our own wire keys, snake_case,
    /// and a dot in one has never been valid. `testADottedComponentCollides`
    /// pins it, so whoever changes the rule finds the other platform first.
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
    ///
    /// For a leaf. A view with children worth naming needs the container
    /// spelling below.
    func payCrossIdentifier(_ identifier: PayCrossTestIdentifiers) -> some View {
        accessibilityIdentifier(identifier.rawValue)
    }

    /// The same, for a view whose children carry identifiers of their own.
    ///
    /// An identifier on a container is inherited by every descendant that is not
    /// already inside an element of its own, and **the container's string wins**.
    /// 0.7.0 named the sheet's content and the stored-card picker this way, and
    /// published `paycross.sheet` on the Pay button and `paycross.savedCards` on
    /// all three picker rows, their bins and `Use a new card`, so the README's
    /// own `app.buttons[payButton]` example found nothing at all.
    ///
    /// `children: .contain` first makes the view an accessibility container, so
    /// the identifier lands on the container itself and everything under it
    /// keeps what it was given. The order is the fix: applied the other way
    /// round it names the boundary and leaves the inheritance where it was.
    func payCrossContainerIdentifier(_ identifier: PayCrossTestIdentifiers) -> some View {
        accessibilityElement(children: .contain)
            .payCrossIdentifier(identifier)
    }
}
#endif
