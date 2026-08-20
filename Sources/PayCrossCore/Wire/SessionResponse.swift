import Foundation

/// `GET session/{id}` on the checkout API.
///
/// Note this is a different shape from the *merchant* API's session resource that
/// the demo harness polls. The SDK sees the checkout view of a session; the
/// merchant backend sees its own. Conflating them was a bug in an earlier pass.
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

/// Everything the checkout page needs to render, decided server-side.
package struct SessionData: Codable, Sendable, Hashable {
    package let locale: String?
    package let returnURL: String?
    package let successURL: String?
    package let fieldGroups: [FieldGroup]?
    package let merchantCountry: String?
    package let saveCardConfig: SaveCardConfig?
    package let savedCards: [WireSavedCard]?

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
    package var allowsSavingCard: Bool { saveCardConfig != nil }

    package init(
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

package struct SaveCardConfig: Codable, Sendable, Hashable {
    package let usage: String?

    package init(usage: String? = nil) { self.usage = usage }
}

/// A saved card as the server sends it.
///
/// Distinct from the presentation-layer `SavedCard`: this is the wire shape, and
/// mapping between them is where the brand string becomes a `CardBrand`.
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

    /// Maps to the type the form uses.
    ///
    /// An unrecognised or absent brand becomes `.unknown`, which validates its
    /// CVV at three digits — the same fallback Android takes for saved cards.
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
    package let fields: [FieldDefinition]?

    package init(key: String, label: String? = nil, fields: [FieldDefinition]? = nil) {
        self.key = key
        self.label = label
        self.fields = fields
    }
}

package struct FieldDefinition: Codable, Sendable, Hashable {
    package let name: String
    package let type: String?
    package let label: String?
    package let placeholder: String?
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

    package init(value: String, label: String? = nil) {
        self.value = value
        self.label = label
    }
}

package struct FieldValidation: Codable, Sendable, Hashable {
    package let pattern: String?
    package let maxLength: Int?
    package let messages: [String: String]?

    enum CodingKeys: String, CodingKey {
        case maxLength = "max_length"
        case pattern, messages
    }

    package init(
        pattern: String? = nil,
        maxLength: Int? = nil,
        messages: [String: String]? = nil
    ) {
        self.pattern = pattern
        self.maxLength = maxLength
        self.messages = messages
    }
}

package enum SessionLifecycle {
    package static let open = "open"
    package static let completed = "completed"
    package static let expired = "expired"
}
