#if os(iOS)
import SwiftUI
import UIKit

@MainActor
enum SheetAnnouncement {

    // WHY: A view appearing does not move VoiceOver focus, so the screen change is announced explicitly.
    static func screenChanged() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    static func post(_ message: String) {
        if #available(iOS 17.0, *) {
            AccessibilityNotification.Announcement(message).post()
        } else {
            // WHY: AccessibilityNotification needs iOS 17, and the SDK targets iOS 16.
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}
#endif
