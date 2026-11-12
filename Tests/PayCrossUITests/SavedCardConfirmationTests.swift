#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class SavedCardConfirmationTests: XCTestCase {

    private let visa = "card_1"
    private let mastercard = "card_2"
    private let host = ViewHost()

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - Pressing the trash

    func testPressingTheTrashOnlyRaisesTheConfirmation() async throws {
        let (model, transport) = try await makeSheet()

        model.requestRemoval(of: try XCTUnwrap(model.form.savedCards.last))

        XCTAssertEqual(model.cardPendingRemoval?.id, mastercard, "the row it sits on")
        XCTAssertNil(model.removalTask, "the press alone must not reach the network")
        let sent = await transport.sent
        XCTAssertFalse(sent.contains { $0.httpMethod == "DELETE" })
        XCTAssertEqual(model.form.savedCards.count, 2)
    }

    // MARK: - Answering it

    func testConfirmingRemovesThatCardAndOnlyThatCard() async throws {
        let (model, transport) = try await makeSheet()

        model.requestRemoval(of: try XCTUnwrap(model.form.savedCards.last))
        model.confirmRemoval()
        await model.removalTask?.value

        let deletes = await transport.sent.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(
            deletes.first?.url?.lastPathComponent, mastercard,
            "the confirmation has to act on the row that raised it"
        )
        XCTAssertEqual(model.form.savedCards.map(\.id), [visa])
        XCTAssertNil(model.cardPendingRemoval, "the prompt goes with the answer")
    }

    func testCancellingRemovesNothing() async throws {
        let (model, transport) = try await makeSheet()

        model.requestRemoval(of: try XCTUnwrap(model.form.savedCards.first))
        model.cancelRemoval()

        XCTAssertNil(model.cardPendingRemoval)
        XCTAssertNil(model.removalTask, "cancel must not reach the network at all")
        let sent = await transport.sent
        XCTAssertFalse(sent.contains { $0.httpMethod == "DELETE" })
        XCTAssertEqual(model.form.savedCards.map(\.id), [visa, mastercard])
    }

    func testConfirmingWithNothingPendingDoesNothing() async throws {
        let (model, transport) = try await makeSheet()

        model.confirmRemoval()

        XCTAssertNil(model.removalTask)
        let sent = await transport.sent
        XCTAssertFalse(sent.contains { $0.httpMethod == "DELETE" })
        XCTAssertEqual(model.form.savedCards.count, 2)
    }

    // MARK: - Whether the trash is offered at all

    func testTheTrashIsDrawnOnlyWhenTheSessionAllowsItAndNothingIsPaying() throws {
        let baseline = try render(allowsRemoval: false, isPaying: false)

        XCTAssertNotEqual(
            try render(allowsRemoval: true, isPaying: false), baseline,
            "a session that allows removal has to draw the control"
        )
        XCTAssertEqual(
            try render(allowsRemoval: true, isPaying: true), baseline,
            "the trash goes away while a payment is being authorized"
        )
        XCTAssertEqual(
            try render(allowsRemoval: false, isPaying: true), baseline
        )
    }

    // MARK: - Plumbing

    private func makeSheet() async throws -> (PaymentSheetModel, StubTransport) {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON.utf8)),
            .init(status: 204, body: Data())
        ])
        let model = PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1",
                brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"),
                expiresAt: nil
            ),
            configuration: Configuration(
                environment: .sandbox,
                testCardPrefill: nil,
                applePayMerchantIdentifier: nil
            ),
            walletAuthorizer: nil,
            deviceCanPay: { false },
            transport: transport
        )
        await model.load()
        XCTAssertEqual(model.form.savedCards.map(\.id), [visa, mastercard])
        XCTAssertTrue(model.allowsCardRemoval)
        return (model, transport)
    }

    private func render(allowsRemoval: Bool, isPaying: Bool) throws -> Data {
        let window = host(
            SavedCardPicker(
                cards: [SavedCard(id: visa, brand: .visa, last4: "1111", expiryLabel: "12/30")],
                selection: .newCard,
                allowsRemoval: allowsRemoval,
                isPaying: isPaying,
                onSelect: { _ in },
                onRemoveRequested: { _ in }
            )
            .padding(20)
            .background(Color(.systemGroupedBackground))
        )
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in window.layer.render(in: context.cgContext) }
        return try XCTUnwrap(image.pngData())
    }


    private var sessionJSON: String {
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
            "saved_cards_config": { "allow_removal": true, "preselect": false }
          }
        }
        """
    }
}
#endif
