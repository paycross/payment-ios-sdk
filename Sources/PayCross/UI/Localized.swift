#if os(iOS)
import Foundation

/// Looks a user-visible string up, merchant bundle first.
///
/// A SwiftUI `Text("Card Number")` in a package resolves its key against
/// `Bundle.main` — the merchant's app — not against ours, so a merchant whose
/// own strings file happens to define one of our labels silently repaints it.
/// Every literal in the sheet goes through here instead, which puts our copy in
/// our bundle and turns that accident into the deliberate override: a merchant
/// who defines one of the keys below in their own `Localizable.strings` gets
/// their wording, and everyone else gets ours.
func L(_ key: String, _ fallback: String) -> String {
    let merchant = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    if merchant != key { return merchant }
    return sdkBundle.localizedString(forKey: key, value: fallback, table: nil)
}

/// Where our own strings live, which differs by how the SDK was installed.
///
/// SwiftPM generates `Bundle.module`. CocoaPods does not: the pod's resources
/// are copied into a `PayCrossLocalizations.bundle` next to the binary, and for
/// a static library that binary is the merchant's app, so the class's own
/// bundle is only the place to start looking from.
///
/// Internal rather than private: `LocalizedTests` reads it through `@testable`.
let sdkBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    let base = Bundle(for: PaymentSheet.self)
    if let url = base.url(forResource: "PayCrossLocalizations", withExtension: "bundle"),
       let bundle = Bundle(url: url) {
        return bundle
    }
    return base
    #endif
}()
#endif
