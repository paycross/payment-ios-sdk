#if os(iOS)
import Foundation
import PayCrossCore

// A SwiftUI Text in a package resolves its key against the merchant's Bundle.main, so every literal goes through L.
// The sheet's own language is searched in the merchant bundle first, since Bundle.localizedString follows the device's languages.
@MainActor
// Keys carry the paycross_ prefix, so no plausible merchant string collides with one by chance.
func L(_ key: String, _ fallback: String, merchant: Bundle? = nil) -> String {
    let app = merchant ?? .main
    let inSheetLanguage = merchant == nil
        ? SheetLanguage.merchantBundle
        : SheetLanguage.lproj(SheetLanguage.tag, in: app)

    if let inSheetLanguage {
        let override = inSheetLanguage.localizedString(forKey: key, value: nil, table: nil)
        if override != key { return override }
    }
    // The merchant app's own resolution is the fallback when it ships no .lproj for the sheet's language.
    let override = app.localizedString(forKey: key, value: nil, table: nil)
    if override != key { return override }
    return SheetLanguage.bundle.localizedString(forKey: key, value: fallback, table: nil)
}

// The template comes from the merchant's bundle, so String(format:) could read a vararg that was never passed.
@MainActor
func L(
    _ key: String,
    _ fallback: String,
    _ argument: String,
    merchant: Bundle? = nil
) -> String {
    Template.fill(L(key, fallback, merchant: merchant), with: argument)
}

// One sheet at a time is assumed, not enforced: a second install would re-language the sheet underneath it.
// Installed twice per payment, first without the network and again when the session's locale arrives.
@MainActor
enum SheetLanguage {
    private(set) static var tag: String = LocaleResolution.defaultLanguage

    private(set) static var bundle: Bundle = sdkBundle

    // Resolved once here, since L runs for every string on every repaint.
    private(set) static var merchantBundle: Bundle?

    // Not derived from tag, since Foundation formats currency for every language and a region setting may differ.
    // Locale.current is kept when only the device had an opinion, so the shopper's own price format is not rebuilt.
    private(set) static var locale: Locale = .current

    static func install(_ resolved: ResolvedLocale) {
        tag = resolved.language
        bundle = lproj(resolved.language, in: sdkBundle) ?? sdkBundle
        merchantBundle = lproj(resolved.language, in: .main)
        locale = resolved.formattingTag.map(Locale.init(identifier:)) ?? .current
    }

    static func reset() {
        tag = LocaleResolution.defaultLanguage
        bundle = sdkBundle
        merchantBundle = lproj(LocaleResolution.defaultLanguage, in: .main)
        locale = .current
    }

    static func lproj(_ language: String, in bundle: Bundle) -> Bundle? {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

// Bundle.module traps rather than returning nil, so under SwiftPM a missing bundle crashes instead of falling back.
let sdkBundle: Bundle = .module
#endif
