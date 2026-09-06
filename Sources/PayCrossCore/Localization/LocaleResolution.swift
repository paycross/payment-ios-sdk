import Foundation

/// Decides which language the payment sheet speaks.
///
/// Pure, and in Core rather than beside the bundle lookup it feeds, so the rule
/// is asserted on Linux on every commit while the `.lproj` lookup it drives only
/// compiles on a Mac. Nothing here throws and nothing here touches a `Bundle`: a
/// tag the SDK cannot speak resolves to English rather than failing, because a
/// shopper reading the wrong language can still pay and a shopper looking at a
/// crashed sheet cannot.
package enum LocaleResolution {

    /// The languages the SDK ships strings for.
    package static let supportedLanguages: Set<String> = ["en", "fr"]

    /// What an unresolvable tag becomes, and what `Package.swift` declares as the
    /// package's `defaultLocalization`.
    package static let defaultLanguage = "en"

    /// Resolves the sheet's language.
    ///
    /// The three rungs are tried in order and the first one that offers anything
    /// at all decides. An explicit `de` from a merchant therefore resolves to
    /// English; it does not fall through to a French device. That is the hosted
    /// checkout page's own rule — one candidate chosen, then matched once — and
    /// it keeps a deliberate `configure(locale:)` from being quietly overruled by
    /// a setting the merchant cannot see.
    ///
    /// - Parameters:
    ///   - override: the merchant's `Configuration.locale`.
    ///   - session: `SessionData.locale`, exactly as the server sent it.
    ///   - device: the shopper's ranked preferences, e.g. `Locale.preferredLanguages`.
    ///   - supported: the languages to match against. A parameter so a test can
    ///     pin the rule without depending on what the SDK happens to ship today.
    package static func resolve(
        override: String? = nil,
        session: String? = nil,
        device: [String] = [],
        supported: Set<String> = supportedLanguages
    ) -> String {
        let rungs = [normalized(override), normalized(session), device.flatMap(normalized)]
        for rung in rungs where !rung.isEmpty {
            return match(rung, supported: supported) ?? defaultLanguage
        }
        return defaultLanguage
    }

    /// Exact tag first, then its primary subtag, one candidate at a time.
    ///
    /// Per candidate rather than every exact match before any subtag match: a
    /// device that ranks `fr-CA` above `en` is asking for French, and sweeping
    /// the list for exact matches first would hand it English.
    private static func match(_ tags: [String], supported: Set<String>) -> String? {
        for tag in tags {
            if supported.contains(tag) { return tag }
            let primary = String(tag.prefix { $0 != "-" })
            if !primary.isEmpty, supported.contains(primary) { return primary }
        }
        return nil
    }

    /// One tag, lowercased and separated by hyphens, or nothing at all.
    ///
    /// `_` is accepted because POSIX-style `fr_CA` arrives both from server
    /// payloads and from `Locale.identifier`, and rejecting it would silently
    /// un-translate a session that named its language perfectly well. A blank is
    /// dropped rather than treated as an answer, so a merchant who reads an
    /// empty string out of their own config still gets the session's language.
    private static func normalized(_ tag: String?) -> [String] {
        guard let tag else { return [] }
        let cleaned = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return cleaned.isEmpty ? [] : [cleaned]
    }
}
