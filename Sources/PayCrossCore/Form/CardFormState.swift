import Foundation

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

    package var rowTitle: String {
        "\(brand.displayName) •••• \(last4)"
    }
}

package enum CardEntrySource: Sendable, Hashable {
    case newCard
    case saved(SavedCard)

    package var isNewCard: Bool {
        if case .newCard = self { return true }
        return false
    }
}

package struct CardFormState: Sendable, Equatable {
    // Held beside the selection, because removing a saved card must change the row and the selected entry mode together.
    package var savedCards: [SavedCard] = []
    package var source: CardEntrySource = .newCard
    package private(set) var panDigits = ""
    package private(set) var expiryDigits = ""
    package private(set) var cvvDigits = ""
    package var cardholderName = ""
    package var saveCard = false
    package var inlineError: String?

    package static let maxExpiryDigits = 4

    package init(source: CardEntrySource = .newCard, savedCards: [SavedCard] = []) {
        self.source = source
        self.savedCards = savedCards
    }

    // MARK: - Derived

    package var brand: CardBrand {
        switch source {
        case .newCard: CardBrand.detect(panDigits)
        case .saved(let card): card.brand
        }
    }

    // A saved card's own brand sets the CVV length: an Amex keeps its 4-digit CID, which `.unknown` would cap at 3.
    package var cvvBrand: CardBrand {
        brand
    }

    package var expiryMonth: String {
        String(expiryDigits.prefix(2))
    }

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

package enum CardFormEvent: Sendable, Equatable {
    case panChanged(String)
    case expiryChanged(String)
    case cvvChanged(String)
    case nameChanged(String)
    case saveCardToggled(Bool)
    case sourceSelected(CardEntrySource)
    case savedCardRemoved(uuid: String)
    case paySubmitted
    case declined(message: String)
    case walletDeclined(message: String)
}

package enum CardFormReducer {
    package static func reduce(state: inout CardFormState, event: CardFormEvent) {
        switch event {
        case .panChanged(let raw):
            state.clearError()
            let digits = raw.filter(\.isNumber)
            state.setPAN(String(digits.prefix(state.brandLimitFor(digits))))
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
            state.setCVV("")

        case .savedCardRemoved(let uuid):
            state.clearError()
            state.savedCards.removeAll { $0.id == uuid }
            guard case .saved(let card) = state.source, card.id == uuid else { return }
            reduce(state: &state, event: .sourceSelected(.newCard))

        case .paySubmitted:
            // PCI DSS 3.3.1 forbids keeping the CVV after authorization, so it is cleared on submit.
            state.setCVV("")

        case .declined(let message):
            state.inlineError = message
            state.setCVV("")

        case .walletDeclined(let message):
            // PCI DSS 3.3.1 covers data kept after authorization; this card was never authorized, so the CVV stays.
            state.inlineError = message
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

package enum CardEntryFormatter {

    // Amex is 4-6-5 in the wild, but every brand is grouped in fours to match Android.
    package static func groupPAN(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 4).map { offset in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: min(4, digits.count - offset))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    package static func slashExpiry(_ digits: String) -> String {
        guard digits.count > 2 else { return digits }
        return digits.prefix(2) + "/" + digits.dropFirst(2)
    }
}
