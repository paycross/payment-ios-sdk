#if os(iOS)
import SwiftUI
import UIKit

/// Speaks something that appeared on its own.
///
/// VoiceOver reads what the shopper moves to. A decline banner arrives without
/// anyone moving anywhere, so a shopper using VoiceOver watched the Pay button
/// go quiet and heard nothing at all: the sheet had told them why, in a sentence
/// they had no reason to go looking for.
@MainActor
enum SheetAnnouncement {

    /// Tells VoiceOver the screen changed under it, so it re-orients and reads
    /// from the top of whatever is modal now.
    ///
    /// A system alert did this for free. The confirmations the sheet draws are
    /// ordinary views, and a view appearing moves nobody's focus: without this
    /// a shopper pressed a card's trash and heard silence, with focus still on
    /// the trash of a card the sheet was already asking about.
    static func screenChanged() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// The seam is `ErrorBanner.announce`, which a test injects. This is only
    /// the default it carries, so there is nothing here to swap.
    static func post(_ message: String) {
        if #available(iOS 17.0, *) {
            AccessibilityNotification.Announcement(message).post()
        } else {
            // The 16 fallback. `AccessibilityNotification` is iOS 17, and this
            // SDK's deployment target is 16.
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}
#endif
