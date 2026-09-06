import Foundation

/// What the sheet resolved to: the language of its words, and the locale its
/// amounts are formatted in.
///
/// Two answers rather than one because they are clamped differently. The SDK
/// ships strings for a fixed set of languages, so `language` is always one of
/// those. Foundation formats currency for any locale at all, so `formattingTag`
/// is whatever was asked for, unclamped — a German device keeps `12,34 €` while
/// reading English words, and a Swiss-French session gets Swiss-French digits.
package struct ResolvedLocale: Sendable, Equatable {

    /// One of the languages the SDK ships strings for.
    package let language: String

    /// The tag the amount is formatted with, as it was supplied. Never empty.
    package let formattingTag: String

    package init(language: String, formattingTag: String) {
        self.language = language
        self.formattingTag = formattingTag
    }
}

/// Decides which language the payment sheet speaks, and how it writes an amount.
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

    /// Resolves the sheet's language and its amount formatting.
    ///
    /// **Language falls through.** The merchant's override, then the session's
    /// locale, then each of the device's preferences in turn, are matched one at
    /// a time — exact tag first, then primary subtag — and the first that names a
    /// language the SDK ships wins. A candidate the SDK cannot speak is passed
    /// over rather than ending the search, so a merchant asking for German on a
    /// French session gets the French sheet rather than the English one. This is
    /// the hosted checkout page's rule, which matches each candidate separately.
    ///
    /// **Formatting does not.** It is simply the first candidate anybody
    /// supplied, unclamped, because Foundation can format an amount in a locale
    /// the SDK has no words for. That is deliberately not always the same locale
    /// as the language: a shopper on a German phone should read `12,34 €`
    /// whatever tongue the labels around it are in.
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
    ) -> ResolvedLocale {
        let candidates = ([override, session].compactMap { $0 } + device).compactMap(cleaned)
        return ResolvedLocale(
            language: match(candidates, supported: supported) ?? defaultLanguage,
            formattingTag: candidates.first ?? defaultLanguage
        )
    }

    /// The first candidate naming a language we ship, exact tag before primary
    /// subtag, one candidate at a time.
    ///
    /// Per candidate rather than every exact match before any subtag match: a
    /// device that ranks `fr-CA` above `en` is asking for French, and sweeping
    /// the list for exact matches first would hand it English.
    private static func match(_ tags: [String], supported: Set<String>) -> String? {
        for tag in tags {
            let lowered = tag.lowercased()
            if supported.contains(lowered) { return lowered }
            let primary = String(lowered.prefix { $0 != "-" })
            if !primary.isEmpty, supported.contains(primary) { return primary }
        }
        return nil
    }

    /// One usable tag, or nothing.
    ///
    /// Case and region are kept, because this same string formats the amount and
    /// `fr-CH` is not `fr`. `_` becomes `-` because POSIX-style `fr_CA` arrives
    /// both from server payloads and from `Locale.identifier`, and rejecting it
    /// would silently un-translate a session that named its language perfectly
    /// well. A blank is dropped rather than treated as an answer, so a merchant
    /// who reads an empty string out of their own config still gets a turn for
    /// the session and the device.
    private static func cleaned(_ tag: String) -> String? {
        let trimmed = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return trimmed.isEmpty ? nil : trimmed
    }
}
