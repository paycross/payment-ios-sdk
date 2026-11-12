import Foundation

package struct SessionResponse: Codable, Sendable, Hashable {
    package let sessionID: String
    package let status: String?
    package let latestTransactionID: String?
    package let data: SessionData?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case latestTransactionID = "latest_transaction_id"
        case status, data
    }

    package init(
        sessionID: String,
        status: String? = nil,
        latestTransactionID: String? = nil,
        data: SessionData? = nil
    ) {
        self.sessionID = sessionID
        self.status = status
        self.latestTransactionID = latestTransactionID
        self.data = data
    }
}

package struct SessionData: Codable, Sendable, Hashable {
    package let locale: String?
    package let returnURL: String?
    package let successURL: String?
    package let fieldGroups: [FieldGroup]?
    package let merchantCountry: String?
    package let saveCardConfig: SaveCardConfig?
    package let savedCards: [WireSavedCard]?
    package let savedCardsConfig: SavedCardsConfig?
    package let wallets: WalletsAvailability?
    package let branding: Branding?
    // No caller reads this, but the backend still sends it; keep the decode.
    package let accountFunding: Bool?

    enum CodingKeys: String, CodingKey {
        case returnURL = "return_url"
        case successURL = "success_url"
        case fieldGroups = "field_groups"
        case merchantCountry = "merchant_country"
        case saveCardConfig = "save_card_config"
        case savedCards = "saved_cards"
        case savedCardsConfig = "saved_cards_config"
        case accountFunding = "account_funding"
        case locale, wallets, branding
    }

    package var allowsSavingCard: Bool { saveCardConfig != nil }

    // defaults to off when the session omits the block.
    package var allowsSavedCardRemoval: Bool { savedCardsConfig?.allowRemoval ?? false }

    package var preselectsSavedCard: Bool { savedCardsConfig?.preselect ?? false }

    package init(
        locale: String? = nil,
        returnURL: String? = nil,
        successURL: String? = nil,
        fieldGroups: [FieldGroup]? = nil,
        merchantCountry: String? = nil,
        saveCardConfig: SaveCardConfig? = nil,
        savedCards: [WireSavedCard]? = nil,
        savedCardsConfig: SavedCardsConfig? = nil,
        wallets: WalletsAvailability? = nil,
        branding: Branding? = nil,
        accountFunding: Bool? = nil
    ) {
        self.locale = locale
        self.returnURL = returnURL
        self.successURL = successURL
        self.fieldGroups = fieldGroups
        self.merchantCountry = merchantCountry
        self.saveCardConfig = saveCardConfig
        self.savedCards = savedCards
        self.savedCardsConfig = savedCardsConfig
        self.wallets = wallets
        self.branding = branding
        self.accountFunding = accountFunding
    }

    // A throw here drops the whole session, and WalletGate reads that nil as wallet permission.
    // Every CodingKeys case must be decoded here, since there is no synthesised init.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        returnURL = try container.decodeIfPresent(String.self, forKey: .returnURL)
        successURL = try container.decodeIfPresent(String.self, forKey: .successURL)
        fieldGroups = try container.decodeIfPresent([FieldGroup].self, forKey: .fieldGroups)
        merchantCountry = try container.decodeIfPresent(String.self, forKey: .merchantCountry)
        saveCardConfig = try container.decodeIfPresent(SaveCardConfig.self, forKey: .saveCardConfig)
        savedCards = try container.decodeIfPresent([WireSavedCard].self, forKey: .savedCards)
        // Losing this block costs two affordances; throwing would drop the field groups too.
        savedCardsConfig = (try? container.decodeIfPresent(
            SavedCardsConfig.self, forKey: .savedCardsConfig
        )) ?? nil
        wallets = (try? container.decodeIfPresent(WalletsAvailability.self, forKey: .wallets)) ?? nil
        // An unreadable branding block costs only the default accent.
        branding = (try? container.decodeIfPresent(Branding.self, forKey: .branding)) ?? nil
        accountFunding = container.decodeLenientBoolIfPresent(forKey: .accountFunding)
    }
}

// A value this SDK cannot read is nil, not false, and never throws, so one bad field does not drop the message.
private extension KeyedDecodingContainer {
    func decodeLenientBoolIfPresent(forKey key: Key) -> Bool? {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return nil }

        if let flag = try? decode(Bool.self, forKey: key) { return flag }

        if let number = try? decode(Int.self, forKey: key) {
            switch number {
            case 1: return true
            case 0: return false
            default: return nil
            }
        }

        if let text = try? decode(String.self, forKey: key) {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }

        return nil
    }
}

package struct Branding: Codable, Sendable, Hashable {
    package let brandColor: String?

    enum CodingKeys: String, CodingKey {
        case brandColor = "brand_color"
    }

    package init(brandColor: String? = nil) {
        self.brandColor = brandColor
    }
}

// only an explicit false refuses a wallet; a nil member means the server had no opinion. A wallet flag must never throw, or nil would read as permission.
package struct WalletsAvailability: Codable, Sendable, Hashable {
    package let applePay: Bool?
    package let googlePay: Bool?

    enum CodingKeys: String, CodingKey {
        case applePay = "apple_pay"
        case googlePay = "google_pay"
    }

    package init(applePay: Bool? = nil, googlePay: Bool? = nil) {
        self.applePay = applePay
        self.googlePay = googlePay
    }

    // A value that is not an object throws, so SessionData drops the whole block.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        applePay = container.decodeLenientBoolIfPresent(forKey: .applePay)
        googlePay = container.decodeLenientBoolIfPresent(forKey: .googlePay)
    }
}

package struct SavedCardsConfig: Codable, Sendable, Hashable {
    package let allowRemoval: Bool
    package let preselect: Bool

    enum CodingKeys: String, CodingKey {
        case allowRemoval = "allow_removal"
        case preselect
    }

    package init(allowRemoval: Bool = false, preselect: Bool = false) {
        self.allowRemoval = allowRemoval
        self.preselect = preselect
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        allowRemoval = container.decodeLenientBoolIfPresent(forKey: .allowRemoval) ?? false
        preselect = container.decodeLenientBoolIfPresent(forKey: .preselect) ?? false
    }
}

package struct SaveCardConfig: Codable, Sendable, Hashable {
    package let usage: String?

    package init(usage: String? = nil) { self.usage = usage }
}

package struct WireSavedCard: Codable, Sendable, Hashable {
    package let uuid: String
    package let maskedPAN: String
    package let cardBrand: String?
    package let expireMonth: String
    package let expireYear: String
    package let cardholderName: String

    enum CodingKeys: String, CodingKey {
        case maskedPAN = "masked_pan"
        case cardBrand = "card_brand"
        case expireMonth = "expire_month"
        case expireYear = "expire_year"
        case cardholderName = "cardholder_name"
        case uuid
    }

    package init(
        uuid: String,
        maskedPAN: String,
        cardBrand: String? = nil,
        expireMonth: String,
        expireYear: String,
        cardholderName: String
    ) {
        self.uuid = uuid
        self.maskedPAN = maskedPAN
        self.cardBrand = cardBrand
        self.expireMonth = expireMonth
        self.expireYear = expireYear
        self.cardholderName = cardholderName
    }

    // An unknown brand validates a three-digit CVV, since every scheme but Amex uses three.
    package var presentable: SavedCard {
        SavedCard(
            id: uuid,
            brand: cardBrand.map(Self.brand(from:)) ?? .unknown,
            last4: String(maskedPAN.filter(\.isNumber).suffix(4)),
            expiryLabel: "\(expireMonth)/\(String(expireYear.suffix(2)))"
        )
    }

    static func brand(from value: String) -> CardBrand {
        switch value.lowercased().replacingOccurrences(of: " ", with: "") {
        case "visa": .visa
        case "mastercard", "master", "mc": .mastercard
        case "amex", "americanexpress": .amex
        case "discover": .discover
        default: .unknown
        }
    }
}

// MARK: - Server-driven fields

package struct FieldGroup: Codable, Sendable, Hashable {
    package let key: String
    package let label: String?
    package let labels: [String: String]?
    // Nil and false both mean the group is mandatory, since older sessions omit the flag.
    package let optIn: Bool?
    package let fields: [FieldDefinition]?

    enum CodingKeys: String, CodingKey {
        case optIn = "opt_in"
        case key, label, labels, fields
    }

    package init(
        key: String,
        label: String? = nil,
        labels: [String: String]? = nil,
        optIn: Bool? = nil,
        fields: [FieldDefinition]? = nil
    ) {
        self.key = key
        self.label = label
        self.labels = labels
        self.optIn = optIn
        self.fields = fields
    }

    // Opt_in is read leniently, because losing it leaves the group mandatory.
    // Every CodingKeys case must be decoded here, since there is no synthesised init.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        key = try container.decode(String.self, forKey: .key)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        optIn = container.decodeLenientBoolIfPresent(forKey: .optIn)
        fields = try container.decodeIfPresent([FieldDefinition].self, forKey: .fields)
    }

    package var isOptIn: Bool { optIn == true }

    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }
}

package struct FieldDefinition: Codable, Sendable, Hashable {
    package let name: String
    package let type: String?
    package let label: String?
    package let labels: [String: String]?
    package let placeholder: String?
    package let placeholders: [String: String]?
    package let required: Bool?
    package let readonly: Bool?
    package let value: String?
    package let condition: FieldCondition?
    package let options: [FieldOption]?
    package let validation: FieldValidation?

    package init(
        name: String,
        type: String? = nil,
        label: String? = nil,
        labels: [String: String]? = nil,
        placeholder: String? = nil,
        placeholders: [String: String]? = nil,
        required: Bool? = nil,
        readonly: Bool? = nil,
        value: String? = nil,
        condition: FieldCondition? = nil,
        options: [FieldOption]? = nil,
        validation: FieldValidation? = nil
    ) {
        self.name = name
        self.type = type
        self.label = label
        self.labels = labels
        self.placeholder = placeholder
        self.placeholders = placeholders
        self.required = required
        self.readonly = readonly
        self.value = value
        self.condition = condition
        self.options = options
        self.validation = validation
    }

    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }

    package func placeholder(in language: String?) -> String? {
        language.flatMap { placeholders?[$0] } ?? self.placeholder
    }
}

package struct FieldCondition: Codable, Sendable, Hashable {
    package let whenField: String
    package let whenIn: [String]?
    package let display: String?
    package let `default`: String?

    enum CodingKeys: String, CodingKey {
        case whenField = "when"
        case whenIn = "in"
        case display, `default`
    }

    package init(
        whenField: String,
        whenIn: [String]? = nil,
        display: String? = nil,
        default: String? = nil
    ) {
        self.whenField = whenField
        self.whenIn = whenIn
        self.display = display
        self.default = `default`
    }
}

package struct FieldOption: Codable, Sendable, Hashable {
    package let value: String
    package let label: String?
    package let labels: [String: String]?

    package init(value: String, label: String? = nil, labels: [String: String]? = nil) {
        self.value = value
        self.label = label
        self.labels = labels
    }

    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }
}

package struct FieldValidation: Codable, Sendable, Hashable {
    package let pattern: String?
    package let maxLength: Int?
    package let messages: [String: String]?
    package let messagesI18n: [String: [String: String]]?

    enum CodingKeys: String, CodingKey {
        case maxLength = "max_length"
        case messagesI18n = "messages_i18n"
        case pattern, messages
    }

    package init(
        pattern: String? = nil,
        maxLength: Int? = nil,
        messages: [String: String]? = nil,
        messagesI18n: [String: [String: String]]? = nil
    ) {
        self.pattern = pattern
        self.maxLength = maxLength
        self.messages = messages
        self.messagesI18n = messagesI18n
    }

    package func message(_ rule: String, in language: String?) -> String? {
        language.flatMap { messagesI18n?[$0]?[rule] } ?? messages?[rule]
    }
}

package enum SessionLifecycle {
    package static let open = "open"
    package static let completed = "completed"
    package static let expired = "expired"
}
