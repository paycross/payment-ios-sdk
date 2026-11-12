import Foundation

package struct BrowserInfo: Codable, Sendable, Hashable {
    package let userAgent: String
    // WHY: nil must encode as an absent key, not null, so the server can fall back to the request IP.
    package let ipAddress: String?
    package let screenWidth: Int
    package let screenHeight: Int
    package let colorDepth: Int
    // WHY: Minutes west of UTC, the JavaScript sign that 3DS expects: UTC+2 is -120.
    package let timezoneOffset: Int
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

    package static func timezoneOffsetMinutes(
        timeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> Int {
        -timeZone.secondsFromGMT(for: date) / 60
    }

    // WHY: Extension subtags (such as "-u-rg-lvzzzz") fail the backend's max:10 check, so they are dropped.
    package static func clampedLanguageTag(_ tag: String) -> String {
        let maxLength = 10
        var subtags = tag.split(separator: "-").map(String.init)
        if let singleton = subtags.firstIndex(where: { $0.count == 1 }) {
            subtags = Array(subtags[..<singleton])
        }
        var clamped = ""
        for subtag in subtags {
            let candidate = clamped.isEmpty ? subtag : clamped + "-" + subtag
            guard candidate.count <= maxLength else { break }
            clamped = candidate
        }
        // WHY: The backend rejects a blank language, so an all-extension tag falls back to a prefix.
        return clamped.isEmpty ? String(tag.prefix(maxLength)) : clamped
    }
}

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

// WHY: A PAN must not reach a log through string interpolation.
extension CardData: CustomStringConvertible, CustomDebugStringConvertible {
    package var description: String {
        let tail = (pan?.count ?? 0) >= 4 ? String(pan!.suffix(4)) : ""
        let subject = savedUUID.map { "saved:\($0)" } ?? "****\(tail)"
        return "CardData(\(subject), cvv: •••)"
    }

    package var debugDescription: String { description }
}

// WHY: merchantIdentifier is not optional: an omitted one fails Apple Pay key derivation and reads as a decline.
package struct WalletToken: Codable, Sendable {
    package let type: String
    package let data: JSONValue
    package let merchantIdentifier: String

    enum CodingKeys: String, CodingKey {
        case merchantIdentifier = "merchant_identifier"
        case type, data
    }

    // WHY: Trims like WalletGate.offersApplePay: the server compares the identifier byte for byte.
    // WHY: Returns nil rather than trapping: a crash in a merchant's app is worse than no button.
    package static func applePay(data: JSONValue, merchantIdentifier: String) -> WalletToken? {
        let identifier = merchantIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }

        return WalletToken(
            type: "apple_pay",
            data: data,
            merchantIdentifier: identifier
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

    // WHY: The payment method comes from the token: the server refuses a body where the two disagree.
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
