#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// The sheet's half of saved-card removal and preselection.
///
/// Core proves what the reducer does with a removal; these prove the model asks
/// the server first, keeps the row when the server refuses, and reads the two
/// session flags. The path in between — a trash button, a confirmation, a DELETE
/// — is the one that can charge or strand a shopper, and none of it is reachable
/// from the Linux runner.
@MainActor
final class SavedCardRemovalTests: XCTestCase {

    private let visa = "card_1"
    private let mastercard = "card_2"

    // MARK: - Removal

    func testConfirmingARemovalDeletesServerSideThenDropsTheRow() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(status: 204, body: Data())
        ])
        let model = makeModel(transport: transport)
        await model.load()

        XCTAssertEqual(model.form.savedCards.map(\.id), [visa, mastercard])
        XCTAssertTrue(model.allowsCardRemoval)

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value

        let request = await transport.sent[1]
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://checkout.test-pay-cross.com/api/saved-cards/\(visa)"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer header.payload.signature"
        )

        XCTAssertEqual(
            model.form.savedCards.map(\.id), [mastercard],
            "the row must go once the server has taken the card"
        )
        XCTAssertNil(model.form.inlineError)
    }

    /// The row is the shopper's only record of what the server holds. A removal
    /// the server refused must leave it exactly where it was, or the sheet has
    /// promised something it did not do.
    func testAFailedRemovalKeepsTheRowAndShowsTheReason() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(status: 500, body: Data(#"{"error":"boom"}"#.utf8))
        ])
        let model = makeModel(transport: transport)
        await model.load()

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value

        XCTAssertEqual(
            model.form.inlineError, "Could not remove the card. Try again.",
            "a refused removal has to say so, and offer the retry that may work"
        )
        XCTAssertEqual(model.form.savedCards.map(\.id), [visa, mastercard])
    }

    /// Deleting a card the server is in the middle of charging is not a state
    /// worth having, and the picker stays on screen through authorization.
    func testARemovalIsRefusedWhileAPaymentIsInFlight() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(body: Data(#"{"success":true,"transaction_id":"t1"}"#.utf8))
        ])
        let model = makeModel(transport: transport)
        await model.load()

        CardFormReducer.reduce(state: &model.form, event: .sourceSelected(
            .saved(try XCTUnwrap(model.form.savedCards.first))
        ))
        CardFormReducer.reduce(state: &model.form, event: .cvvChanged("123"))
        model.pay()
        XCTAssertTrue(model.isLoading, "the payment has to be in flight for this to prove anything")

        // The refusal is synchronous, so what the payment does next cannot
        // change the outcome.
        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        // Nil is the assertion: the guard returns before a task is ever made.
        XCTAssertNil(model.removalTask, "no removal may even be started mid-payment")

        let sent = await transport.sent
        XCTAssertFalse(
            sent.contains { $0.httpMethod == "DELETE" },
            "no card may be deleted while its payment is being authorized"
        )
        XCTAssertEqual(model.form.savedCards.count, 2)

        // Stops the poll loop the submit started, so it does not outlive the test.
        model.cancel()
    }

    func testRemovalIsOffWhenTheSessionDoesNotAllowIt() async {
        let transport = StubTransport(
            replies: [.init(body: Data(sessionJSON(allowRemoval: false).utf8))]
        )
        let model = makeModel(transport: transport)
        await model.load()

        XCTAssertFalse(model.allowsCardRemoval)
        XCTAssertEqual(model.form.savedCards.count, 2, "the cards are still offered")
    }

    /// A card the server says is not this customer's is in the state the shopper
    /// asked for. Telling them to try again asks them to repeat a request that
    /// has been answered, against a row that could never go.
    func testARemovalThatComesBack404DropsTheRowAnyway() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(status: 404, body: Data(#"{"error":"not found"}"#.utf8))
        ])
        let model = makeModel(transport: transport)
        await model.load()

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value

        XCTAssertEqual(model.form.savedCards.map(\.id), [mastercard])
        XCTAssertNil(model.form.inlineError, "nothing went wrong from here")
    }

    /// Nothing is retryable on a dead session, and the same token is about to
    /// fail the payment itself. "Try again" would be the wrong instruction.
    func testARemovalThatComesBack401ReportsTheSessionNotTheCard() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(status: 401, body: Data())
        ])
        let model = makeModel(transport: transport)
        await model.load()

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value

        XCTAssertEqual(
            model.form.inlineError, "This payment session has expired. Start again."
        )
        XCTAssertEqual(model.form.savedCards.count, 2, "the card is not the problem")
    }

    /// A removal that succeeds after one that failed must not leave the first
    /// one's message standing over a form that is now fine.
    func testASuccessfulRemovalClearsAnEarlierFailuresBanner() async throws {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON(allowRemoval: true).utf8)),
            .init(status: 500, body: Data()),
            .init(status: 204, body: Data())
        ])
        let model = makeModel(transport: transport)
        await model.load()

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value
        XCTAssertNotNil(model.form.inlineError)

        model.removeSavedCard(try XCTUnwrap(model.form.savedCards.first))
        await model.removalTask?.value

        XCTAssertNil(model.form.inlineError, "the banner was about a card that is gone")
        XCTAssertEqual(model.form.savedCards.map(\.id), [mastercard])
    }

    // MARK: - Preselection

    /// Opt-in, and only ever the first card: the server lists them most recently
    /// used first, so that is the one the shopper reaches for.
    func testPreselectPicksTheMostRecentlyUsedCard() async {
        let transport = StubTransport(
            replies: [.init(body: Data(sessionJSON(preselect: true).utf8))]
        )
        let model = makeModel(transport: transport)
        await model.load()

        XCTAssertEqual(model.form.source, .saved(model.form.savedCards[0]))
        XCTAssertEqual(model.form.savedCards[0].id, visa)
    }

    /// The point of the opt-in. Without it the sheet opens on "Use a new card",
    /// exactly as Android does.
    func testWithoutPreselectTheSheetOpensOnANewCard() async {
        let transport = StubTransport(
            replies: [.init(body: Data(sessionJSON(preselect: false).utf8))]
        )
        let model = makeModel(transport: transport)
        await model.load()

        XCTAssertTrue(model.form.source.isNewCard)
    }

    /// The whole safety argument for preselection. A preselected card is not a
    /// tap away from a charge, because it has no CVV yet and cannot be submitted
    /// without one.
    func testAPreselectedCardCannotBePaidWithoutItsCVV() async {
        let transport = StubTransport(
            replies: [.init(body: Data(sessionJSON(preselect: true).utf8))]
        )
        let model = makeModel(transport: transport)
        await model.load()

        XCTAssertFalse(model.form.canSubmit())
        model.pay()
        XCTAssertFalse(model.isLoading, "a preselected card with no CVV must not submit")

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1, "nothing beyond the session fetch may go on the wire")
    }

    // MARK: - Plumbing

    private func sessionJSON(allowRemoval: Bool = false, preselect: Bool = false) -> String {
        """
        {
          "session_id": "sess_1",
          "status": "open",
          "data": {
            "saved_cards": [
              {
                "uuid": "\(visa)", "masked_pan": "411111******1111", "card_brand": "VISA",
                "expire_month": "12", "expire_year": "2030", "cardholder_name": "A PERSON"
              },
              {
                "uuid": "\(mastercard)", "masked_pan": "555555******4444",
                "card_brand": "MasterCard", "expire_month": "01", "expire_year": "2029",
                "cardholder_name": "A PERSON"
              }
            ],
            "saved_cards_config": { "allow_removal": \(allowRemoval), "preselect": \(preselect) }
          }
        }
        """
    }

    private func makeModel(transport: any HTTPTransport) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                expiresAt: nil
            ),
            // Read off the model rather than PayCrossAPI: the static
            // configuration is a process-wide box nothing resets, and this
            // target runs several suites that write to it.
            configuration: Configuration(
                environment: .sandbox,
                testCardPrefill: nil,
                applePayMerchantIdentifier: nil
            ),
            walletAuthorizer: nil,
            deviceCanPay: { false },
            // Never the real one. A model left holding URLSessionTransport would
            // open a socket to the live checkout API from a unit test.
            transport: transport
        )
    }
}
#endif
