#if os(iOS)
import Foundation
import PayCrossCore

/// Looks a user-visible string up: merchant bundle first, then the language this
/// presentation resolved to.
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
/// The merchant bundle is searched first *whatever language the sheet resolved
/// to*. An explicit `configure(locale:)` does not turn overrides off — the two
/// are answers to different questions, and a merchant who has reworded one label
/// still wants their wording when the shopper is French.
///
/// It is searched in the sheet's language first, and only then however the
/// merchant's app would resolve the key itself. `Bundle.localizedString` picks a
/// localization from the *device's* language list and knows nothing about
/// `SheetLanguage`, so asking it directly would hand a French sheet the English
/// override off an English phone: SDK labels in French, the merchant's two
/// reworded ones in English, from the one API call that was supposed to settle
/// the question.
///
/// `merchant` is the bundle searched first, and exists so the tests can stand a
/// bundle of their own in for the merchant's app.
@MainActor
func L(_ key: String, _ fallback: String, merchant: Bundle = .main) -> String {
    if let inSheetLanguage = merchant.path(forResource: SheetLanguage.tag, ofType: "lproj")
        .flatMap(Bundle.init(path:)) {
        let override = inSheetLanguage.localizedString(forKey: key, value: nil, table: nil)
        if override != key { return override }
    }
    // Whatever the merchant's app would resolve it to. Reached when they ship no
    // `.lproj` for the sheet's language, or ship one that does not name this key.
    let override = merchant.localizedString(forKey: key, value: nil, table: nil)
    if override != key { return override }
    return SheetLanguage.bundle.localizedString(forKey: key, value: fallback, table: nil)
}

/// Looks a string up and fills the one placeholder it carries.
///
/// Every key that takes an argument goes through here rather than through
/// `String(format:)`. The lookup reads the merchant's bundle first, so the
/// template is a string the SDK does not own, and `String(format:)` handed a
/// `%d` somebody typed by mistake reads a vararg that was never passed. See
/// `Template.fill`, which Core uses for the same reason.
@MainActor
func L(
    _ key: String,
    _ fallback: String,
    _ argument: String,
    merchant: Bundle = .main
) -> String {
    Template.fill(L(key, fallback, merchant: merchant), with: argument)
}

/// The language the sheet currently speaks.
///
/// Main-actor state rather than an argument threaded through every view, so a
/// `Text` deep inside the form needs no extra parameter to read it.
///
/// One sheet at a time is **assumed, not enforced**. UIKit declines a second
/// presentation over the first, so a second `PaymentSheet` is already broken
/// before its language is; but if one ever got through, its `install` would
/// re-language the sheet underneath it and whichever finished first would
/// `reset` under the other. `PassKitWalletAuthorizer.authorize` guards itself
/// against exactly this, and the guard belongs at `present` if the assumption
/// ever needs to be real.
///
/// Installed twice per payment on purpose: once from what is known without the
/// network, and again the moment the session's own `locale` arrives, which is
/// the only rung that can still change the answer.
@MainActor
enum SheetLanguage {

    /// The language whose `.lproj` is installed, e.g. `fr`.
    private(set) static var tag: String = LocaleResolution.defaultLanguage

    /// Where `L` reads our own copy from.
    ///
    /// Starts as the whole SDK bundle, which negotiates a language the way
    /// Foundation always has. From the first `install` it is one `.lproj`,
    /// because by then the answer is the SDK's to give, not the device's.
    private(set) static var bundle: Bundle = sdkBundle

    /// The locale the amount is formatted in.
    ///
    /// Not derived from `tag`, and deliberately so: the SDK ships words for two
    /// languages and Foundation formats currency for all of them, so a merchant
    /// asking for `de-AT` gets Austrian digits under English labels.
    ///
    /// When nobody but the device had an opinion this is `Locale.current`, not a
    /// locale rebuilt from the device's language list. The two differ for any
    /// shopper whose Region or format settings do not simply follow their
    /// language, and rebuilding one would have quietly rewritten their price.
    private(set) static var locale: Locale = .current

    /// Installs a resolved language and its formatting.
    ///
    /// A missing `.lproj` falls back to the SDK bundle rather than failing: that
    /// is a packaging mistake, and the English underneath it is still a sheet
    /// somebody can pay on.
    static func install(_ resolved: ResolvedLocale) {
        tag = resolved.language
        bundle = sdkBundle.path(forResource: resolved.language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? sdkBundle
        locale = resolved.formattingTag.map(Locale.init(identifier:)) ?? .current
    }

    /// Hands the choice back to Foundation once the sheet is gone, so a language
    /// belongs to the presentation that resolved it and to nothing else.
    static func reset() {
        tag = LocaleResolution.defaultLanguage
        bundle = sdkBundle
        locale = .current
    }
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
