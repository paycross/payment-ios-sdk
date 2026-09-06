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
