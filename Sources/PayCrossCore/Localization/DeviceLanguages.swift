import Foundation

// WHY: `Locale.preferredLanguages` is filtered by the host app's localizations, so an app that ships only `Base.lproj` would hide the shopper's French; `AppleLanguages` is the unfiltered list.
package enum DeviceLanguages {
    package static let appleLanguagesKey = "AppleLanguages"

    package static func preferred(_ defaults: UserDefaults = .standard) -> [String] {
        ranked(raw: defaults.stringArray(forKey: appleLanguagesKey))
    }

    package static func ranked(
        raw: [String]?,
        fallback: @autoclosure () -> [String] = Locale.preferredLanguages
    ) -> [String] {
        guard let raw, !raw.isEmpty else { return fallback() }
        return raw
    }
}
