#if os(iOS)
import Foundation

/// Looks a user-visible string up, merchant bundle first.
///
/// A SwiftUI `Text("Card Number")` in a package resolves its key against
/// `Bundle.main` — the merchant's app — not against ours, so a merchant whose
/// own strings file happens to define one of our labels silently repaints it.
/// Every literal in the sheet goes through here instead, which puts our copy in
/// our bundle and turns that accident into the deliberate override. The keys are
/// prefixed `paycross_` so no plausible app string collides with one by chance:
/// a merchant who wants their own wording has to name the key on purpose, and
/// everyone else gets ours.
///
/// `merchant` is the bundle searched first, and exists so the tests can stand a
/// bundle of their own in for the merchant's app.
func L(_ key: String, _ fallback: String, merchant: Bundle = .main) -> String {
    let override = merchant.localizedString(forKey: key, value: nil, table: nil)
    if override != key { return override }
    return sdkBundle.localizedString(forKey: key, value: fallback, table: nil)
}

/// Where our own strings live, which differs by how the SDK was installed.
///
/// SwiftPM generates `Bundle.module`. CocoaPods does not: the pod's resources
/// are copied into a `PayCrossLocalizations.bundle` next to the binary, and for
/// a static library that binary is the merchant's app, so the class's own
/// bundle is only the place to start looking from.
///
/// The English fallback each call passes is a promise only under CocoaPods:
/// `Bundle.module` traps rather than returning nil when the generated resource
/// bundle is missing, so under SwiftPM a lost bundle crashes here instead of
/// falling back.
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
