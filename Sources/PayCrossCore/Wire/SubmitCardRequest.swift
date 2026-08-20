import Foundation

/// Device characteristics required for 3DS v2 risk assessment.
///
/// The model lives in Core so it can be asserted on Linux; the *collection* of
/// these values is platform-bound and lives in the iOS target.
package struct BrowserInfo: Codable, Sendable, Hashable {
    package let userAgent: String
    package let ipAddress: String
    package let screenWidth: Int
    package let screenHeight: Int
    package let colorDepth: Int
    /// Minutes **west** of UTC, with DST applied — the JavaScript
    /// `Date.getTimezoneOffset()` convention that 3DS expects. A device at UTC+2
    /// reports -120, not +120.
    package let timezoneOffset: Int
    /// BCP-47 language tag, e.g. "en-GB".
    package let language: String
    package let acceptHeader: String
    package let javaEnabled: Bool
    package let javascriptEnabled: Bool

    package static let defaultAcceptHeader =
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    enum CodingKeys: String, CodingKey {
        case userAgent = "user_agent"
        case ipAddress = "ip_address"
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
        case colorDepth = "color_depth"
        case timezoneOffset = "timezone_offset"
        case acceptHeader = "accept_header"
        case javaEnabled = "java_enabled"
        case javascriptEnabled = "javascript_enabled"
        case language
    }

    package init(
        userAgent: String,
        ipAddress: String,
        screenWidth: Int,
        screenHeight: Int,
        colorDepth: Int = 24,
        timezoneOffset: Int,
        language: String,
        acceptHeader: String = BrowserInfo.defaultAcceptHeader,
        javaEnabled: Bool = false,
        javascriptEnabled: Bool = true
    ) {
        self.userAgent = userAgent
        self.ipAddress = ipAddress
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.colorDepth = colorDepth
        self.timezoneOffset = timezoneOffset
        self.language = language
        self.acceptHeader = acceptHeader
        self.javaEnabled = javaEnabled
        self.javascriptEnabled = javascriptEnabled
    }

    /// Minutes west of UTC for `timeZone` at `date`, matching the Kotlin.
    package static func timezoneOffsetMinutes(
        timeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> Int {
        -timeZone.secondsFromGMT(for: date) / 60
    }

    /// The backend validates `language` as `max:10`, and EMVCo 3DS caps
    /// browserLanguage at 8 characters, but a full BCP-47 identifier can carry
    /// extension subtags: a device whose Region differs from the language's
    /// home region produces "en-US-u-rg-lvzzzz", which fails validation and
    /// kills the payment server-side after submit already returned 200. Keep
    /// the meaningful prefix (language, script, region) and drop the rest.
    package static func clampedLanguageTag(_ tag: String) -> String {
        let maxLength = 10
        var subtags = tag.split(separator: "-").map(String.init)
        // A single-character subtag ("u", "x") starts an extension or
        // private-use section; nothing after it is a language fact.
        if let singleton = subtags.firstIndex(where: { $0.count == 1 }) {
            subtags = Array(subtags[..<singleton])
        }
        var clamped = ""
        for subtag in subtags {
            let candidate = clamped.isEmpty ? subtag : clamped + "-" + subtag
            guard candidate.count <= maxLength else { break }
            clamped = candidate
        }
        // Purely private-use ("x-private") or an oversized first subtag leaves
        // nothing; the backend also requires the field non-blank, so send a
        // hard-truncated prefix rather than an empty string.
        return clamped.isEmpty ? String(tag.prefix(maxLength)) : clamped
    }
}

/// Card details for submission. New card or saved card; never both.
public struct CardData: Codable, Sendable, Hashable {
    public let savedUUID: String?
    public let cardholderName: String?
    public let pan: String?
    public let expireYear: String?
    public let expireMonth: String?
    public let cvv: String
    public let save: Bool?

    enum CodingKeys: String, CodingKey {
        case savedUUID = "saved_uuid"
        case cardholderName = "cardholder_name"
        case expireYear = "expire_year"
        case expireMonth = "expire_month"
        case pan, cvv, save
    }

    /// A newly entered card.
    public static func newCard(
        cardholderName: String,
        pan: String,
        expireMonth: String,
        expireYear: String,
        cvv: String,
        save: Bool? = nil
    ) -> CardData {
        CardData(
            savedUUID: nil,
            cardholderName: cardholderName,
            pan: pan,
            expireYear: expireYear,
            expireMonth: expireMonth,
            cvv: cvv,
            save: save
        )
    }

    /// A previously saved card, re-confirmed with its CVV.
    public static func savedCard(uuid: String, cvv: String) -> CardData {
        CardData(
            savedUUID: uuid,
            cardholderName: nil,
            pan: nil,
            expireYear: nil,
            expireMonth: nil,
            cvv: cvv,
            save: nil
        )
    }
}

/// Redacted so a PAN cannot reach a log through string interpolation.
extension CardData: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let tail = (pan?.count ?? 0) >= 4 ? String(pan!.suffix(4)) : ""
        let subject = savedUUID.map { "saved:\($0)" } ?? "****\(tail)"
        return "CardData(\(subject), cvv: •••)"
    }

    public var debugDescription: String { description }
}

public struct SubmitCardRequest: Codable, Sendable {
    public let session: String
    public let paymentMethod: String
    public let card: CardData?
    // Follows BrowserInfo's access level, now `package`.
    package let browserInfo: BrowserInfo
    public let fieldGroups: [String: [String: String]]?

    enum CodingKeys: String, CodingKey {
        case paymentMethod = "payment_method"
        case browserInfo = "browser_info"
        case fieldGroups = "field_groups"
        case session, card
    }

    // Capped at `package` by the browserInfo parameter, same as above.
    package init(
        session: String,
        card: CardData,
        browserInfo: BrowserInfo,
        fieldGroups: [String: [String: String]]? = nil
    ) {
        self.session = session
        self.paymentMethod = "card"
        self.card = card
        self.browserInfo = browserInfo
        self.fieldGroups = fieldGroups
    }
}

extension SubmitCardRequest: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "SubmitCardRequest(method: \(paymentMethod), card: \(card?.description ?? "nil"))"
    }

    public var debugDescription: String { description }
}
