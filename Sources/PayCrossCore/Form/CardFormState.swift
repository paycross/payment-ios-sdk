import Foundation

/// A card the shopper has previously saved.
package struct SavedCard: Sendable, Hashable, Identifiable {
    package let id: String
    package let brand: CardBrand
    package let last4: String
    package let expiryLabel: String

    package init(id: String, brand: CardBrand, last4: String, expiryLabel: String) {
        self.id = id
        self.brand = brand
        self.last4 = last4
        self.expiryLabel = expiryLabel
    }
}

/// Whether the shopper is entering a new card or re-confirming a saved one.
///
/// Modelled as a sum type rather than `selectedCardID: String?` alongside a
/// `isNewCard: Bool`, which makes "saved card selected but id is nil" unrepresentable.
package enum CardEntrySource: Sendable, Hashable {
    case newCard
    case saved(SavedCard)

    package var isNewCard: Bool {
        if case .newCard = self { return true }
        return false
    }
}

/// Everything the card form holds.
///
/// Digits only — no formatting characters are ever stored, so the value that goes
/// on the wire needs no cleaning step. Formatting is a display concern.
package struct CardFormState: Sendable, Equatable {
    package var source: CardEntrySource = .newCard
    package private(set) var panDigits = ""
    /// MMYY, exactly as Android stores it.
    package private(set) var expiryDigits = ""
    package private(set) var cvvDigits = ""
    package var cardholderName = ""
    package var saveCard = false
    /// Set after a decline; cleared as soon as the shopper edits anything.
    package var inlineError: String?

    package static let maxExpiryDigits = 4

    package init(source: CardEntrySource = .newCard) {
        self.source = source
    }

    // MARK: - Derived

    package var brand: CardBrand {
        switch source {
        case .newCard: CardBrand.detect(panDigits)
        case .saved(let card): card.brand
        }
    }

    /// A saved card's CVV is validated at 3 digits, matching Android's use of
    /// `CardType.UNKNOWN` on that path.
    package var cvvBrand: CardBrand {
        source.isNewCard ? brand : .unknown
    }

    package var expiryMonth: String {
        String(expiryDigits.prefix(2))
    }

    /// Android stores YY and prefixes "20" when submitting.
    package var expiryYear: String {
        expiryDigits.count > 2 ? "20" + expiryDigits.dropFirst(2) : ""
    }

    // MARK: - Display formatting

    package var formattedPAN: String {
        CardEntryFormatter.groupPAN(panDigits)
    }

    package var formattedExpiry: String {
        CardEntryFormatter.slashExpiry(expiryDigits)
    }

    // MARK: - Validation

    package func isPANValid() -> Bool {
        !source.isNewCard || CardValidator.isValidPAN(panDigits)
    }

    package func isExpiryValid(now: Date = Date()) -> Bool {
        guard source.isNewCard else { return true }
        guard expiryDigits.count == Self.maxExpiryDigits else { return false }
        return CardValidator.isValidExpiry(month: expiryMonth, year: expiryYear, now: now)
    }

    package func isCVVValid() -> Bool {
        CardValidator.isValidCVV(cvvDigits, brand: cvvBrand)
    }

    package func isNameValid() -> Bool {
        !source.isNewCard || CardValidator.isValidCardholderName(cardholderName)
    }

    package func canSubmit(now: Date = Date()) -> Bool {
        isPANValid() && isExpiryValid(now: now) && isCVVValid() && isNameValid()
    }

    /// The wire payload for this form. Nil when the form is not submittable.
    package func cardData(now: Date = Date()) -> CardData? {
        guard canSubmit(now: now) else { return nil }
        switch source {
        case .newCard:
            return .newCard(
                cardholderName: cardholderName,
                pan: panDigits,
                expireMonth: expiryMonth,
                expireYear: expiryYear,
                cvv: cvvDigits,
                save: saveCard ? true : nil
            )
        case .saved(let card):
            return .savedCard(uuid: card.id, cvv: cvvDigits)
        }
    }
}

/// Events the form reacts to.
package enum CardFormEvent: Sendable, Equatable {
    case panChanged(String)
    case expiryChanged(String)
    case cvvChanged(String)
    case nameChanged(String)
    case saveCardToggled(Bool)
    case sourceSelected(CardEntrySource)
    case paySubmitted
    case declined(message: String)
}

package enum CardFormReducer {

    package static func reduce(state: inout CardFormState, event: CardFormEvent) {
        switch event {
        case .panChanged(let raw):
            state.clearError()
            let digits = raw.filter(\.isNumber)
            state.setPAN(String(digits.prefix(state.brandLimitFor(digits))))
            // A brand change can invalidate an already-typed CVV length.
            state.trimCVVToBrand()

        case .expiryChanged(let raw):
            state.clearError()
            state.setExpiry(String(raw.filter(\.isNumber).prefix(CardFormState.maxExpiryDigits)))

        case .cvvChanged(let raw):
            state.clearError()
            state.setCVV(String(raw.filter(\.isNumber).prefix(state.cvvBrand.cvvLength)))

        case .nameChanged(let raw):
            state.clearError()
            state.cardholderName = raw.uppercased()

        case .saveCardToggled(let on):
            state.saveCard = on

        case .sourceSelected(let source):
            state.source = source
            state.clearError()
            // Switching entry mode must not carry a CVV across.
            state.setCVV("")

        case .paySubmitted:
            // PCI DSS 3.3.1: sensitive authentication data must not be retained
            // after authorization. The CVV is gone the moment it is handed off.
            state.setCVV("")

        case .declined(let message):
            state.inlineError = message
            state.setCVV("")
        }
    }
}

private extension CardFormState {
    mutating func setPAN(_ value: String) { panDigits = value }
    mutating func setExpiry(_ value: String) { expiryDigits = value }
    mutating func setCVV(_ value: String) { cvvDigits = value }

    mutating func clearError() { inlineError = nil }

    func brandLimitFor(_ digits: String) -> Int {
        CardBrand.detect(digits).maxPANLength
    }

    mutating func trimCVVToBrand() {
        let limit = cvvBrand.cvvLength
        if cvvDigits.count > limit {
            cvvDigits = String(cvvDigits.prefix(limit))
        }
    }
}

/// Display formatting for card entry fields.
package enum CardEntryFormatter {

    /// Groups a PAN in fours. Amex is 4-6-5 in the wild, but Android groups
    /// everything in fours and this mirrors it.
    package static func groupPAN(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 4).map { offset in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: min(4, digits.count - offset))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    /// MMYY becomes MM/YY once past the month.
    package static func slashExpiry(_ digits: String) -> String {
        guard digits.count > 2 else { return digits }
        return digits.prefix(2) + "/" + digits.dropFirst(2)
    }
}
