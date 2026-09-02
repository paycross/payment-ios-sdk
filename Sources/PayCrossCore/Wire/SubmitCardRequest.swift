import Foundation

/// Device characteristics required for 3DS v2 risk assessment.
///
/// The model lives in Core so it can be asserted on Linux; the *collection* of
/// these values is platform-bound and lives in the iOS target.
package struct BrowserInfo: Codable, Sendable, Hashable {
    package let userAgent: String
    /// The submit-card Lambda derives this from the request (the Cloudflare
    /// connecting-IP header, falling back to the source IP) whenever the client
    /// sends none, so the SDK no longer resolves the shopper's public IP itself
    /// -- there is no third-party lookup here. A client-supplied value still
    /// wins: `nil` must encode as an absent key, not `"ip_address": null`, or
    /// the server has nothing to fall back to.
    package let ipAddress: String?
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
        ipAddress: String? = nil,
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
package struct CardData: Codable, Sendable, Hashable {
    package let savedUUID: String?
    package let cardholderName: String?
    package let pan: String?
    package let expireYear: String?
    package let expireMonth: String?
    package let cvv: String
    package let save: Bool?

    enum CodingKeys: String, CodingKey {
        case savedUUID = "saved_uuid"
        case cardholderName = "cardholder_name"
        case expireYear = "expire_year"
        case expireMonth = "expire_month"
        case pan, cvv, save
    }

    /// A newly entered card.
    package static func newCard(
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
    package static func savedCard(uuid: String, cvv: String) -> CardData {
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
    package var description: String {
        let tail = (pan?.count ?? 0) >= 4 ? String(pan!.suffix(4)) : ""
        let subject = savedUUID.map { "saved:\($0)" } ?? "****\(tail)"
        return "CardData(\(subject), cvv: •••)"
    }

    package var debugDescription: String { description }
}

/// A wallet payment's token, as the submit endpoint takes it.
///
/// `merchantIdentifier` is not optional, and that is the point. Apple's key
/// derivation hashes the merchant's own Apple merchant identifier into every
/// token's key, and the edge reads an absent field as "this is a web token" --
/// so an omitted identifier is not refused anywhere. It makes the vault derive
/// the environment default key, fail to open the envelope, and answer a 400
/// that reads exactly like a decline. A non-optional field cannot be omitted by
/// the encoder, which is the only guarantee available here.
///
/// The value itself is a presence flag once it reaches the edge: it is compared
/// against the signed session token's `apple_merchant_id` claim and then
/// discarded, and the claim's copy is what reaches the vault. Nothing this SDK
/// sends can steer key derivation.
package struct WalletToken: Codable, Sendable {
    package let type: String
    package let data: JSONValue
    package let merchantIdentifier: String

    enum CodingKeys: String, CodingKey {
        case merchantIdentifier = "merchant_identifier"
        case type, data
    }

    /// The only way to build an Apple Pay token, and it refuses an empty
    /// identifier.
    ///
    /// Nil rather than a `precondition`: the caller has already asked
    /// `WalletGate.offersApplePay`, which refuses an empty identifier too, so
    /// reaching here with one is a bug -- and crashing a merchant's app is a
    /// worse answer to that bug than not offering the button.
    package static func applePay(data: JSONValue, merchantIdentifier: String) -> WalletToken? {
        guard !merchantIdentifier.isEmpty else { return nil }

        return WalletToken(
            type: "apple_pay",
            data: data,
            merchantIdentifier: merchantIdentifier
        )
    }
}

package struct SubmitCardRequest: Codable, Sendable {
    package let session: String
    package let paymentMethod: String
    package let card: CardData?
    package let walletToken: WalletToken?
    package let browserInfo: BrowserInfo
    package let fieldGroups: [String: [String: String]]?

    enum CodingKeys: String, CodingKey {
        case paymentMethod = "payment_method"
        case walletToken = "wallet_token"
        case browserInfo = "browser_info"
        case fieldGroups = "field_groups"
        case session, card
    }

    package init(
        session: String,
        card: CardData,
        browserInfo: BrowserInfo,
        fieldGroups: [String: [String: String]]? = nil
    ) {
        self.session = session
        self.paymentMethod = "card"
        self.card = card
        self.walletToken = nil
        self.browserInfo = browserInfo
        self.fieldGroups = fieldGroups
    }

    /// A wallet payment. The payment method is taken from the token rather
    /// than passed separately, because the edge refuses a body where the two
    /// disagree and two arguments would be two chances to make them.
    package init(
        session: String,
        walletToken: WalletToken,
        browserInfo: BrowserInfo,
        fieldGroups: [String: [String: String]]? = nil
    ) {
        self.session = session
        self.paymentMethod = walletToken.type
        self.card = nil
        self.walletToken = walletToken
        self.browserInfo = browserInfo
        self.fieldGroups = fieldGroups
    }
}

extension SubmitCardRequest: CustomStringConvertible, CustomDebugStringConvertible {
    package var description: String {
        "SubmitCardRequest(method: \(paymentMethod), card: \(card?.description ?? "nil"))"
    }

    package var debugDescription: String { description }
}
