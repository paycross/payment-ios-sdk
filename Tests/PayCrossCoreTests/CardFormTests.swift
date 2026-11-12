import XCTest
@testable import PayCrossCore

final class CardFormTests: XCTestCase {

    func testASavedCardNamesItselfTheSameWayEverywhere() {
        let card = SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")
        XCTAssertEqual(card.rowTitle, "Visa •••• 1111")
    }

    private var june2026: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 15
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func fill(_ state: inout CardFormState) {
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
    }

    // MARK: - Input handling

    func testOnlyDigitsAreStored() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .panChanged("4111 1111-1111abc1111"))
        XCTAssertEqual(state.panDigits, "4111111111111111")
    }

    func testPANIsBoundedByBrand() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .panChanged("41111111111111111111111"))
        XCTAssertEqual(state.panDigits.count, 19, "Visa tops out at 19")

        var amex = CardFormState()
        CardFormReducer.reduce(state: &amex, event: .panChanged("3782822463100051234"))
        XCTAssertEqual(amex.panDigits.count, 15, "Amex is 15")
    }

    func testExpiryIsFourDigits() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .expiryChanged("12/30/99"))
        XCTAssertEqual(state.expiryDigits, "1230")
        XCTAssertEqual(state.expiryMonth, "12")
        XCTAssertEqual(state.expiryYear, "2030")
    }

    func testNameIsUppercased() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("a person"))
        XCTAssertEqual(state.cardholderName, "A PERSON")
    }

    func testCVVIsTrimmedWhenTheBrandChanges() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .panChanged("378282246310005"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("1234"))
        XCTAssertEqual(state.cvvDigits, "1234")

        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        XCTAssertEqual(state.cvvDigits, "123", "a Visa CVV is 3 digits")
    }

    // MARK: - Formatting

    func testPANIsGroupedInFours() {
        XCTAssertEqual(CardEntryFormatter.groupPAN("4111111111111111"), "4111 1111 1111 1111")
        XCTAssertEqual(CardEntryFormatter.groupPAN("411"), "411")
        XCTAssertEqual(CardEntryFormatter.groupPAN("41111"), "4111 1")
        XCTAssertEqual(CardEntryFormatter.groupPAN(""), "")
    }

    func testExpiryGainsASlashAfterTheMonth() {
        XCTAssertEqual(CardEntryFormatter.slashExpiry("1"), "1")
        XCTAssertEqual(CardEntryFormatter.slashExpiry("12"), "12")
        XCTAssertEqual(CardEntryFormatter.slashExpiry("123"), "12/3")
        XCTAssertEqual(CardEntryFormatter.slashExpiry("1230"), "12/30")
    }

    // MARK: - Validation and submission

    func testCompleteFormCanSubmit() {
        var state = CardFormState()
        fill(&state)
        XCTAssertTrue(state.canSubmit(now: june2026))
    }

    func testIncompleteFormCannotSubmit() {
        var state = CardFormState()
        fill(&state)

        var noName = state
        CardFormReducer.reduce(state: &noName, event: .nameChanged(""))
        XCTAssertFalse(noName.canSubmit(now: june2026))

        var badPAN = state
        CardFormReducer.reduce(state: &badPAN, event: .panChanged("4111111111111112"))
        XCTAssertFalse(badPAN.canSubmit(now: june2026))

        var shortCVV = state
        CardFormReducer.reduce(state: &shortCVV, event: .cvvChanged("12"))
        XCTAssertFalse(shortCVV.canSubmit(now: june2026))

        var expired = state
        CardFormReducer.reduce(state: &expired, event: .expiryChanged("0526"))
        XCTAssertFalse(expired.canSubmit(now: june2026))
    }

    func testPartialExpiryIsNotValid() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .expiryChanged("12"))
        XCTAssertFalse(state.isExpiryValid(now: june2026))
    }

    func testNewCardPayloadUsesFourDigitYear() throws {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .saveCardToggled(true))

        let card = try XCTUnwrap(state.cardData(now: june2026))
        XCTAssertEqual(card.pan, "4111111111111111")
        XCTAssertEqual(card.expireMonth, "12")
        XCTAssertEqual(card.expireYear, "2030")
        XCTAssertEqual(card.save, true)
        XCTAssertNil(card.savedUUID)
    }

    func testSaveIsOmittedRatherThanFalse() throws {
        var state = CardFormState()
        fill(&state)
        let card = try XCTUnwrap(state.cardData(now: june2026))
        XCTAssertNil(card.save)
    }

    func testInvalidFormProducesNoPayload() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .panChanged("4111"))
        XCTAssertNil(state.cardData(now: june2026))
    }

    // MARK: - Saved cards

    private var savedCard: SavedCard {
        SavedCard(id: "uuid-1", brand: .visa, last4: "1111", expiryLabel: "12/30")
    }

    func testSavedCardNeedsOnlyACVV() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        XCTAssertFalse(state.canSubmit(now: june2026))

        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        XCTAssertTrue(state.canSubmit(now: june2026))

        let card = try XCTUnwrap(state.cardData(now: june2026))
        XCTAssertEqual(card.savedUUID, "uuid-1")
        XCTAssertEqual(card.cvv, "123")
        XCTAssertNil(card.pan, "a saved card must never resend the PAN")
        XCTAssertNil(card.save)
    }

    func testSavedAmexCardTakesAFourDigitCVV() {
        var state = CardFormState()
        CardFormReducer.reduce(
            state: &state,
            event: .sourceSelected(.saved(
                SavedCard(id: "u", brand: .amex, last4: "0005", expiryLabel: "12/30")
            ))
        )
        XCTAssertEqual(state.cvvBrand, .amex)

        CardFormReducer.reduce(state: &state, event: .cvvChanged("1234"))
        XCTAssertEqual(state.cvvDigits, "1234", "an Amex CID is 4 digits")
        XCTAssertTrue(state.isCVVValid())

        var short = state
        CardFormReducer.reduce(state: &short, event: .cvvChanged("123"))
        XCTAssertFalse(short.isCVVValid(), "3 digits is not a complete CID")
    }

    func testSavedVisaCardStillTakesThreeDigits() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        XCTAssertEqual(state.cvvBrand, .visa)

        CardFormReducer.reduce(state: &state, event: .cvvChanged("1234"))
        XCTAssertEqual(state.cvvDigits, "123", "a Visa CVV is 3 digits")
        XCTAssertTrue(state.isCVVValid())
    }

    func testSwitchingSourceClearsTheCVV() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        XCTAssertEqual(state.cvvDigits, "", "a CVV must not carry across entry modes")
    }

    // MARK: - Removing a saved card

    private var twoSavedCards: [SavedCard] {
        [
            savedCard,
            SavedCard(id: "uuid-2", brand: .mastercard, last4: "4444", expiryLabel: "01/29")
        ]
    }

    func testRemovingACardDropsItFromThePicker() {
        var state = CardFormState(savedCards: twoSavedCards)
        CardFormReducer.reduce(state: &state, event: .savedCardRemoved(uuid: "uuid-1"))

        XCTAssertEqual(state.savedCards.map(\.id), ["uuid-2"])
    }

    func testRemovingTheSelectedCardFallsBackToNewCardAndClearsTheCVV() {
        var state = CardFormState(savedCards: twoSavedCards)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))

        CardFormReducer.reduce(state: &state, event: .savedCardRemoved(uuid: "uuid-1"))

        XCTAssertTrue(state.source.isNewCard)
        XCTAssertEqual(state.cvvDigits, "", "the CVV belonged to a card that is gone")
        XCTAssertEqual(state.savedCards.map(\.id), ["uuid-2"])
    }

    func testRemovingAnUnselectedCardKeepsTheSelectionAndTheCVV() {
        var state = CardFormState(savedCards: twoSavedCards)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))

        CardFormReducer.reduce(state: &state, event: .savedCardRemoved(uuid: "uuid-2"))

        XCTAssertEqual(state.source, .saved(savedCard))
        XCTAssertEqual(state.cvvDigits, "123")
        XCTAssertEqual(state.savedCards.map(\.id), ["uuid-1"])
    }

    func testRemovingACardThatIsAlreadyGoneChangesNothing() {
        var state = CardFormState(savedCards: twoSavedCards)
        CardFormReducer.reduce(state: &state, event: .savedCardRemoved(uuid: "uuid-1"))
        let after = state

        CardFormReducer.reduce(state: &state, event: .savedCardRemoved(uuid: "uuid-1"))
        XCTAssertEqual(state, after)
    }

    func testAPreselectedCardStillCannotPayWithoutItsCVV() {
        var state = CardFormState(savedCards: twoSavedCards)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))

        XCTAssertFalse(state.canSubmit(now: june2026))
        XCTAssertNil(state.cardData(now: june2026))
    }

    // MARK: - PCI

    func testCVVIsClearedOnSubmit() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .paySubmitted)

        XCTAssertEqual(state.cvvDigits, "")
        XCTAssertEqual(state.panDigits, "4111111111111111", "the PAN stays so the form can be re-armed")
    }

    func testDeclineClearsTheCVVAndShowsTheMessage() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .declined(message: "Card declined"))

        XCTAssertEqual(state.cvvDigits, "")
        XCTAssertEqual(state.inlineError, "Card declined")
    }

    func testAWalletDeclineKeepsTheCVV() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .walletDeclined(message: "Apple Pay failed"))

        XCTAssertEqual(state.cvvDigits, "123", "the wallet never saw this card")
        XCTAssertEqual(state.inlineError, "Apple Pay failed")
        XCTAssertEqual(state.panDigits, "4111111111111111")
    }

    func testACardDeclineStillClearsTheCVV() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .declined(message: "Card declined"))

        XCTAssertEqual(state.cvvDigits, "")
    }

    func testEditingClearsTheError() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .declined(message: "Card declined"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("1"))
        XCTAssertNil(state.inlineError)
    }
}
