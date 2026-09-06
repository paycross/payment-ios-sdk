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
    /// **Formatting does not.** It is the first candidate that is *shaped* like a
    /// language tag, unclamped, because Foundation can format an amount in a
    /// locale the SDK has no words for. That is deliberately not always the same
    /// locale as the language: a shopper on a German phone should read `12,34 €`
    /// whatever tongue the labels around it are in.
    ///
    /// The shape check is there so a typo cannot do double damage. A merchant
    /// who writes `f-r` picks neither the words nor the number format; the
    /// session or the device supplies the formatting instead. It is syntax only:
    /// this cannot tell a language that exists from one that does not, so a
    /// well-formed tag naming no real language is still used to format.
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
            formattingTag: candidates.first(where: isWellFormed) ?? defaultLanguage
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
