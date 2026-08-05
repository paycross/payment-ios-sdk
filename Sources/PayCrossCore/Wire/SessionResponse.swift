import Foundation

/// `GET session/{id}` on the checkout API.
///
/// Note this is a different shape from the *merchant* API's session resource that
/// the demo harness polls. The SDK sees the checkout view of a session; the
/// merchant backend sees its own. Conflating them was a bug in an earlier pass.
public struct SessionResponse: Codable, Sendable, Hashable {
    public let sessionID: String
    public let status: String?
    public let latestTransactionID: String?
    public let data: SessionData?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case latestTransactionID = "latest_transaction_id"
        case status, data
    }

    public init(
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

/// Everything the checkout page needs to render, decided server-side.
public struct SessionData: Codable, Sendable, Hashable {
    public let locale: String?
    public let returnURL: String?
    public let successURL: String?
    public let fieldGroups: [FieldGroup]?
    public let merchantCountry: String?
    public let saveCardConfig: SaveCardConfig?
    public let savedCards: [WireSavedCard]?

    enum CodingKeys: String, CodingKey {
        case returnURL = "return_url"
        case successURL = "success_url"
        case fieldGroups = "field_groups"
        case merchantCountry = "merchant_country"
        case saveCardConfig = "save_card_config"
        case savedCards = "saved_cards"
        case locale
    }

    /// The save-card checkbox appears only when the server configured it.
    public var allowsSavingCard: Bool { saveCardConfig != nil }

    public init(
        locale: String? = nil,
        returnURL: String? = nil,
        successURL: String? = nil,
        fieldGroups: [FieldGroup]? = nil,
        merchantCountry: String? = nil,
        saveCardConfig: SaveCardConfig? = nil,
        savedCards: [WireSavedCard]? = nil
    ) {
        self.locale = locale
        self.returnURL = returnURL
        self.successURL = successURL
        self.fieldGroups = fieldGroups
        self.merchantCountry = merchantCountry
        self.saveCardConfig = saveCardConfig
        self.savedCards = savedCards
    }
}

public struct SaveCardConfig: Codable, Sendable, Hashable {
    public let usage: String?

    public init(usage: String? = nil) { self.usage = usage }
}

/// A saved card as the server sends it.
///
/// Distinct from the presentation-layer `SavedCard`: this is the wire shape, and
/// mapping between them is where the brand string becomes a `CardBrand`.
public struct WireSavedCard: Codable, Sendable, Hashable {
    public let uuid: String
    public let maskedPAN: String
    public let cardBrand: String?
    public let expireMonth: String
    public let expireYear: String
    public let cardholderName: String

    enum CodingKeys: String, CodingKey {
        case maskedPAN = "masked_pan"
        case cardBrand = "card_brand"
        case expireMonth = "expire_month"
        case expireYear = "expire_year"
        case cardholderName = "cardholder_name"
        case uuid
    }

    public init(
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

    /// Maps to the type the form uses.
    ///
    /// An unrecognised or absent brand becomes `.unknown`, which validates its
    /// CVV at three digits — the same fallback Android takes for saved cards.
    public var presentable: SavedCard {
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

public struct FieldGroup: Codable, Sendable, Hashable {
    public let key: String
    public let label: String?
    public let fields: [FieldDefinition]?

    public init(key: String, label: String? = nil, fields: [FieldDefinition]? = nil) {
        self.key = key
        self.label = label
        self.fields = fields
    }
}

public struct FieldDefinition: Codable, Sendable, Hashable {
    public let name: String
    public let type: String?
    public let label: String?
    public let placeholder: String?
    public let required: Bool?
    public let readonly: Bool?
    public let value: String?
    public let condition: FieldCondition?
    public let options: [FieldOption]?
    public let validation: FieldValidation?

    public init(
        name: String,
        type: String? = nil,
        label: String? = nil,
        placeholder: String? = nil,
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
        self.placeholder = placeholder
        self.required = required
        self.readonly = readonly
        self.value = value
        self.condition = condition
        self.options = options
        self.validation = validation
    }
}

/// Shows or hides a field based on another field's value.
public struct FieldCondition: Codable, Sendable, Hashable {
    public let whenField: String
    public let whenIn: [String]?
    public let display: String?
    public let `default`: String?

    enum CodingKeys: String, CodingKey {
        case whenField = "when"
        case whenIn = "in"
        case display, `default`
    }

    public init(
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

public struct FieldOption: Codable, Sendable, Hashable {
    public let value: String
    public let label: String?

    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label
    }
}

public struct FieldValidation: Codable, Sendable, Hashable {
    public let pattern: String?
    public let maxLength: Int?
    public let messages: [String: String]?

    enum CodingKeys: String, CodingKey {
        case maxLength = "max_length"
        case pattern, messages
    }

    public init(
        pattern: String? = nil,
        maxLength: Int? = nil,
        messages: [String: String]? = nil
    ) {
        self.pattern = pattern
        self.maxLength = maxLength
        self.messages = messages
    }
}

public enum SessionLifecycle {
    public static let open = "open"
    public static let completed = "completed"
    public static let expired = "expired"
}
