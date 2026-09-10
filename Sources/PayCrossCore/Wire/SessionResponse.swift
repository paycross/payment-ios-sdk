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
    package let savedCardsConfig: SavedCardsConfig?
    package let wallets: WalletsAvailability?
    /// The merchant's back-office branding. Only the brand colour is read.
    package let branding: Branding?
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
        case savedCardsConfig = "saved_cards_config"
        case accountFunding = "account_funding"
        case locale, wallets, branding
    }

    /// The save-card checkbox appears only when the server configured it.
    package var allowsSavingCard: Bool { saveCardConfig != nil }

    /// Whether the sheet may offer to delete a stored card. Off unless the
    /// session says otherwise, so a session minted before the backend shipped
    /// the block shows no delete affordance rather than one whose endpoint may
    /// not be routed yet.
    package var allowsSavedCardRemoval: Bool { savedCardsConfig?.allowRemoval ?? false }

    /// Whether to open with the most recently used stored card already picked.
    /// A merchant opt-in, and off by default.
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
        // Read leniently for the same reason as `wallets`, with the opposite
        // risk: both flags default to off, so losing the block costs only the
        // two affordances it enables, while throwing would take the field
        // groups and the saved cards down with it.
        savedCardsConfig = (try? container.decodeIfPresent(
            SavedCardsConfig.self, forKey: .savedCardsConfig
        )) ?? nil
        wallets = (try? container.decodeIfPresent(WalletsAvailability.self, forKey: .wallets)) ?? nil
        // Lenient for the same reason as the two above, and the cheapest of the
        // three to lose: a colour the SDK cannot read costs the merchant's
        // default accent, and the sheet falls back to the platform's.
        branding = (try? container.decodeIfPresent(Branding.self, forKey: .branding)) ?? nil
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

/// The merchant's branding, as the back office published it.
///
/// One colour, applied to both appearances: the branding record holds no
/// light/dark variants and no mode field, so per-appearance brand colours stay
/// a code-set feature. A merchant with a dark-mode palette already has a
/// developer writing the configure call.
package struct Branding: Codable, Sendable, Hashable {

    /// `#RRGGBB`, as typed into the back office. Parsed leniently, and worth
    /// nothing but the accent colour if it cannot be read.
    package let brandColor: String?

    enum CodingKeys: String, CodingKey {
        case brandColor = "brand_color"
    }

    package init(brandColor: String? = nil) {
        self.brandColor = brandColor
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

/// What the merchant asked this checkout to do with the stored cards it lists.
///
/// A sibling of `saved_cards` rather than a field on it, because the wire keeps
/// `saved_cards` a flat array and there is nowhere on a list to hang a flag.
/// Both members default to false: an absent key, an absent block and an
/// unreadable value all mean "the merchant did not ask for this".
package struct SavedCardsConfig: Codable, Sendable, Hashable {
    /// Whether the sheet offers to delete a stored card.
    package let allowRemoval: Bool
    /// Whether the sheet opens with the most recently used card already picked.
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
    /// The same heading in each language the checkout renders, keyed by language
    /// tag. Sent beside `label` rather than instead of it, and it does not
    /// depend on the session's own locale.
    package let labels: [String: String]?
    /// Whether the shopper may decline this group.
    ///
    /// Set on a group the merchant offers rather than requires -- a shipping
    /// address the shopper only fills in when it differs from the billing one.
    /// Absent on every other group, and on every session minted before the flag
    /// existed, so nil and false say the same thing: the group is mandatory and
    /// behaves exactly as it always has.
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

    /// Decoded by hand so that a flag this SDK cannot read costs only the flag.
    ///
    /// `field_groups` is one array inside one `SessionData`, so a throw here
    /// takes every group on the sheet down with it and `PaymentSheet` swallows
    /// that and draws a form the server never described. Losing `opt_in` alone
    /// leaves the group mandatory, which is the direction a shopper can still
    /// pay in. Same reasoning as `wallets` and `saved_cards_config` above, and
    /// the same lenient reading: `true`, `"true"` and `1` are all yes.
    ///
    /// Anything added to `CodingKeys` has to be decoded here as well; there is
    /// no longer a synthesised initialiser to fall back on.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        key = try container.decode(String.self, forKey: .key)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        optIn = container.decodeLenientBoolIfPresent(forKey: .optIn)
        fields = try container.decodeIfPresent([FieldDefinition].self, forKey: .fields)
    }

    /// Whether the shopper has to ask for this group before it counts.
    package var isOptIn: Bool { optIn == true }

    /// The heading in the sheet's language, or the singular value when the
    /// session predates the maps or names no such language.
    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }
}

package struct FieldDefinition: Codable, Sendable, Hashable {
    package let name: String
    package let type: String?
    package let label: String?
    /// The field's label in each language the checkout renders.
    package let labels: [String: String]?
    package let placeholder: String?
    /// The field's placeholder in each language. Absent whenever the field has
    /// no placeholder at all, so a nil map is not an empty one.
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

    /// The label in the sheet's language, or the singular value when the session
    /// predates the maps or names no such language.
    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }

    /// The placeholder in the sheet's language, under the same rule.
    package func placeholder(in language: String?) -> String? {
        language.flatMap { placeholders?[$0] } ?? self.placeholder
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
    /// The option's label in each language the checkout renders.
    package let labels: [String: String]?

    package init(value: String, label: String? = nil, labels: [String: String]? = nil) {
        self.value = value
        self.label = label
        self.labels = labels
    }

    /// The label in the sheet's language, or the singular value when the session
    /// predates the maps or names no such language.
    package func label(in language: String?) -> String? {
        language.flatMap { labels?[$0] } ?? self.label
    }
}

package struct FieldValidation: Codable, Sendable, Hashable {
    package let pattern: String?
    package let maxLength: Int?
    package let messages: [String: String]?
    /// The same sentences in each language, language outermost and the rule
    /// name inside it — the opposite nesting to `messages`.
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

    /// One rule's sentence in the sheet's language, or the singular value when
    /// the session predates the maps or names no such language.
    package func message(_ rule: String, in language: String?) -> String? {
        language.flatMap { messagesI18n?[$0]?[rule] } ?? messages?[rule]
    }
}

package enum SessionLifecycle {
    package static let open = "open"
    package static let completed = "completed"
    package static let expired = "expired"
}
