import Foundation

/// The shopper's own ranked list of languages.
///
/// The device rung of the ladder in `LocaleResolution` used to read
/// `Locale.preferredLanguages`, which is not that list: Foundation intersects
/// the shopper's list with the **host app's** localizations before answering. A
/// merchant app shipping only `Base.lproj` therefore reported `["en"]` on a
/// phone set to French, and the French the SDK ships — which it ships whatever
/// the app around it ships — could never be reached from the device. Measured on
/// the simulator with `AppleLanguages = ("fr-FR")`: the sheet stayed English,
/// while `configure(locale:)` and the session's own locale both worked.
///
/// `AppleLanguages` in the standard defaults is the unfiltered list, in the
/// shopper's own order. An app that writes the key into its own domain to offer
/// an in-app language switch shadows the global one, and that is the right
/// answer: it has said what its user reads.
///
/// **What has been measured, and what has not.** On the simulator, with the key
/// set in the app's own domain and a demo shipping only `Base.lproj`, the sheet
/// renders French. A real device keeps the shopper's Settings language in the
/// global domain instead, which the standard defaults also search; that half
/// follows from the search list rather than from a measurement, and wants one
/// check on hardware.
///
/// Reaching this rung at all takes a session that names no language the SDK
/// ships: the API fills a session's `locale` with `en` when the merchant sets
/// none, and that matches, so the ladder stops above here. A pending API
/// change stops it defaulting the field.
package enum DeviceLanguages {

    /// Where the system keeps the list.
    package static let appleLanguagesKey = "AppleLanguages"

    /// The list, most preferred first.
    ///
    /// The parameter is a test seam. Nothing is written through it: this reads
    /// one key the OS owns and puts nothing of its own anywhere.
    package static func preferred(_ defaults: UserDefaults = .standard) -> [String] {
        ranked(raw: defaults.stringArray(forKey: appleLanguagesKey))
    }

    /// The rule, without the read, so it is asserted on Linux.
    ///
    /// `Locale.preferredLanguages` is the fallback rather than an empty list: a
    /// device with no such key still has a language, and the filtered list is a
    /// better answer than none at all. It is autoclosed so the platform is only
    /// asked when there is nothing to prefer.
    package static func ranked(
        raw: [String]?,
        fallback: @autoclosure () -> [String] = Locale.preferredLanguages
    ) -> [String] {
        guard let raw, !raw.isEmpty else { return fallback() }
        return raw
    }
}
