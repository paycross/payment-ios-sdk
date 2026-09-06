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

    /// The real post, and the seam a test replaces.
    ///
    /// There is no VoiceOver in a test process and nothing observable when this
    /// runs for real, so the alternative to a seam is not testing the highest
    /// value item on the accessibility floor at all.
    static var post: (String) -> Void = { message in
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
