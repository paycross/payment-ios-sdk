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

    /// The tag the amount is formatted with, as it was supplied.
    ///
    /// Nil when neither the merchant nor the session offered a usable one. That
    /// is not "use English": it means nobody but the shopper's own device has an
    /// opinion, and the caller should hand the formatter `Locale.current`, which
    /// carries a region and the shopper's explicit format settings that a
    /// language tag out of `preferredLanguages` does not.
    package let formattingTag: String?

    package init(language: String, formattingTag: String?) {
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
    /// **Formatting is a different answer.** It is the first *asked-for* tag —
    /// the override, then the session — that is shaped like a language tag, and
    /// it is not clamped to what the SDK ships, because Foundation formats an
    /// amount in locales the SDK has no words for. So a merchant asking for
    /// `de-AT` gets Austrian digits under English labels.
    ///
    /// The device is deliberately **not** a candidate here. Its language list
    /// carries no region and none of the shopper's format settings, so rebuilding
    /// a locale from it would write some shoppers a different price than
    /// `Locale.current` does. `formattingTag` is nil in that case and the caller
    /// reaches for `Locale.current` itself, which is what the SDK did before it
    /// spoke a second language.
    ///
    /// The shape check is there so a typo cannot do double damage. A merchant
    /// who writes `français` picks neither the words nor the number format; the
    /// session gets its turn, and failing that the device's own locale does. It
    /// is syntax only: it cannot tell a language that exists from one that does
    /// not, so a well-formed tag for a language the SDK ships no strings for is
    /// still what the amount is formatted in.
    ///
    /// - Parameters:
    ///   - override: the merchant's `Configuration.locale`.
    ///   - session: `SessionData.locale`, exactly as the server sent it.
    ///   - device: the shopper's ranked preferences, e.g. `Locale.preferredLanguages`.
    ///   - supported: the languages to match against, in any case. A parameter so
    ///     a test can pin the rule without depending on what the SDK ships today.
    package static func resolve(
        override: String? = nil,
        session: String? = nil,
        device: [String] = [],
        supported: Set<String> = supportedLanguages
    ) -> ResolvedLocale {
        let asked = [override, session].compactMap { $0 }.compactMap(cleaned)
        let candidates = asked + device.compactMap(cleaned)
        return ResolvedLocale(
            language: match(candidates, supported: supported) ?? defaultLanguage,
            formattingTag: asked.first(where: isWellFormed)
        )
    }

    /// Whether a tag is shaped like a language tag: a 2-3 letter language, then
    /// any number of 1-8 character alphanumeric subtags.
    ///
    /// Syntax only, and deliberately narrow. `Locale(identifier:)` accepts
    /// anything at all and quietly formats a nonsense tag with root data, so the
    /// choice is between checking the shape here or discovering the typo in a
    /// screenshot of a price. Foundation is not asked to validate: it has no
    /// "is this real" to give, and its answer would differ between Darwin and
    /// the Linux build this is asserted on.
    ///
    /// Language matching does *not* go through this. `fr-` reads as French, and
    /// should: the words degrade to something a shopper can read, while a number
    /// format guessed from a broken tag has nothing to degrade to.
    private static func isWellFormed(_ tag: String) -> Bool {
        let subtags = tag.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = subtags.first,
              (2...3).contains(language.count),
              language.allSatisfy(isASCIILetter)
        else { return false }

        return subtags.dropFirst().allSatisfy { subtag in
            (1...8).contains(subtag.count) && subtag.allSatisfy(isASCIIAlphanumeric)
        }
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// The first candidate naming a language we ship, exact tag before primary
    /// subtag, one candidate at a time.
    ///
    /// Per candidate rather than every exact match before any subtag match: a
    /// device that ranks `fr-CA` above `en` is asking for French, and sweeping
    /// the list for exact matches first would hand it English.
    private static func match(_ tags: [String], supported: Set<String>) -> String? {
        // Lowercased here rather than trusted: the parameter is a test seam, and
        // a caller passing ["EN"] should get English rather than silently match
        // nothing at all.
        let supported = Set(supported.map { $0.lowercased() })
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
