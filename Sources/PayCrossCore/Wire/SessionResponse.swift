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
    package let wallets: WalletsAvailability?
    // Decoded for the wire contract and deliberately unread: no source file
    // consumes this after the gate stopped checking it. Kept because the
    // backend keeps writing it and dropping the decode would be a silent
    // wire-contract regression.
    package let accountFunding: Bool?

    enum CodingKeys: String, CodingKey {
        case returnURL = "return_url"
        case successURL = "success_url"
        case fieldGroups = "field_groups"
        case merchantCountry = "merchant_country"
        case saveCardConfig = "save_card_config"
        case savedCards = "saved_cards"
        case accountFunding = "account_funding"
        case locale, wallets
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
        savedCards: [WireSavedCard]? = nil,
        wallets: WalletsAvailability? = nil,
        accountFunding: Bool? = nil
    ) {
        self.locale = locale
        self.returnURL = returnURL
        self.successURL = successURL
        self.fieldGroups = fieldGroups
        self.merchantCountry = merchantCountry
        self.saveCardConfig = saveCardConfig
        self.savedCards = savedCards
        self.wallets = wallets
        self.accountFunding = accountFunding
    }

    /// Decoded by hand so that a malformed wallet flag costs only itself.
    ///
    /// `SessionData` decodes as one value, so a throw anywhere in it takes the
    /// field groups and the saved cards down too, and `PaymentSheet` swallows
    /// that error and renders a form the server never described. For the two
    /// wallet fields the loss also inverts the answer: session data becomes
    /// nil, and `WalletGate` reads nil as permission, so a merchant who
    /// switched Apple Pay off in a shape iOS cannot parse would get the button.
    /// Every other field keeps throwing, because a malformed field group is a
    /// real failure with no safe reading.
    ///
    /// Anything added to `CodingKeys` has to be decoded here as well; there is
    /// no longer a synthesised initialiser to fall back on.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        returnURL = try container.decodeIfPresent(String.self, forKey: .returnURL)
        successURL = try container.decodeIfPresent(String.self, forKey: .successURL)
        fieldGroups = try container.decodeIfPresent([FieldGroup].self, forKey: .fieldGroups)
        merchantCountry = try container.decodeIfPresent(String.self, forKey: .merchantCountry)
        saveCardConfig = try container.decodeIfPresent(SaveCardConfig.self, forKey: .saveCardConfig)
        savedCards = try container.decodeIfPresent([WireSavedCard].self, forKey: .savedCards)
        wallets = (try? container.decodeIfPresent(WalletsAvailability.self, forKey: .wallets)) ?? nil
        accountFunding = container.decodeLenientBoolIfPresent(forKey: .accountFunding)
    }
}

/// Reads a wire boolean the backend may have spelled as a string or a number.
///
/// `true`, `"true"` and `1` are all yes; `false`, `"false"` and `0` are all no.
/// Anything else is nil -- the server said something this SDK cannot read, which
/// is not the same as the server saying no. Never throws, because the callers
/// that use it have decided a bad value costs one field rather than the whole
/// message.
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

/// Which wallets this session's snapshot allows, as the backend recorded them.
///
/// Both the block and every member are optional, and that is load-bearing
/// rather than defensive: a session snapshotted before the backend shipped
/// `wallets` carries no block, and a member the server had no opinion about
/// arrives null. Only an explicit `false` is a refusal, which is what
/// `WalletGate` reads and what the checkout page and the Android SDK both do.
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

    /// Each member is read leniently and independently, so one flag the SDK
    /// cannot parse never costs the other one or the session around it.
    ///
    /// This still throws when the whole value is not an object, and that is
    /// deliberate: `SessionData` catches it and drops the block, which the gate
    /// already treats as "the server had no opinion".
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        applePay = container.decodeLenientBoolIfPresent(forKey: .applePay)
        googlePay = container.decodeLenientBoolIfPresent(forKey: .googlePay)
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
    /// CVV at three digits. That is a guess, and the only safe one: every scheme
    /// but Amex is three. The backend does send `card_brand`.
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
