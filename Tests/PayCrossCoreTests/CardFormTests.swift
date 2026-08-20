import XCTest
@testable import PayCrossCore

final class CardFormTests: XCTestCase {

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

    /// Typing an Amex 4-digit CVV then changing to a Visa PAN must not leave an
    /// over-length CVV behind.
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

    /// Android sends `save` as null rather than false when unticked.
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

    /// Android validates a saved card's CVV against CardType.UNKNOWN, i.e. 3 digits,
    /// regardless of the saved card's brand.
    func testSavedCardCVVIsThreeDigits() {
        var state = CardFormState()
        CardFormReducer.reduce(
            state: &state,
            event: .sourceSelected(.saved(
                SavedCard(id: "u", brand: .amex, last4: "0005", expiryLabel: "12/30")
            ))
        )
        CardFormReducer.reduce(state: &state, event: .cvvChanged("1234"))
        XCTAssertEqual(state.cvvDigits, "123")
        XCTAssertTrue(state.isCVVValid())
    }

    func testSwitchingSourceClearsTheCVV() {
        var state = CardFormState()
        fill(&state)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(savedCard)))
        XCTAssertEqual(state.cvvDigits, "", "a CVV must not carry across entry modes")
    }

    // MARK: - PCI

    /// PCI DSS 3.3.1 forbids retaining sensitive authentication data after
    /// authorization. The CVV must not survive the submit.
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

    func testEditingClearsTheError() {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .declined(message: "Card declined"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("1"))
        XCTAssertNil(state.inlineError)
    }
}
