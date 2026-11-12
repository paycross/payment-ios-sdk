import Foundation

package struct ResolvedLocale: Sendable, Equatable {
    package let language: String
    package let formattingTag: String?

    package init(language: String, formattingTag: String?) {
        self.language = language
        self.formattingTag = formattingTag
    }
}

package enum LocaleResolution {
    package static let supportedLanguages: Set<String> = ["en", "fr"]

    // Must match defaultLocalization in Package.swift.
    package static let defaultLanguage = "en"

    package static func resolve(
        override: String? = nil,
        session: String? = nil,
        device: [String] = [],
        supported: Set<String> = supportedLanguages
    ) -> ResolvedLocale {
        let asked = [override, session].compactMap { $0 }.compactMap(cleaned)
        // Candidates match one at a time, so a device ranking fr-CA above en gets French.
        let candidates = asked + device.compactMap(cleaned)
        // The device list has no region; nil formattingTag means use Locale.current.
        return ResolvedLocale(
            language: match(candidates, supported: supported) ?? defaultLanguage,
            formattingTag: asked.first(where: isWellFormed)
        )
    }

    // Locale(identifier:) formats nonsense with root data, so the shape is checked here.
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

    // Fr- still matches French; only the amount format needs a well-formed tag.
    private static func match(_ tags: [String], supported: Set<String>) -> String? {
        // A caller may pass supported languages in any case.
        let supported = Set(supported.map { $0.lowercased() })
        for tag in tags {
            let lowered = tag.lowercased()
            if supported.contains(lowered) { return lowered }
            let primary = String(lowered.prefix { $0 != "-" })
            if !primary.isEmpty, supported.contains(primary) { return primary }
        }
        return nil
    }

    // fr_CA arrives from server payloads and Locale.identifier, so _ becomes -.
    private static func cleaned(_ tag: String) -> String? {
        let trimmed = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return trimmed.isEmpty ? nil : trimmed
    }
}
