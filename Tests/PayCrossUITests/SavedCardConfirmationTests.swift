#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// The two steps between pressing the trash and the card being gone.
///
/// `SavedCardRemovalTests` starts after the shopper has said yes, and proves
/// what the server call does. This starts one step earlier, at the press, and
/// covers the pair that can delete a card nobody meant to delete: a trash wired
/// to the wrong row, and a confirmation whose Cancel removes the card anyway.
///
/// The press itself is dispatched through the model rather than through a
/// synthesised touch. SwiftUI renders these controls as neither `UIView`s nor
/// materialised accessibility elements — a hosted sheet reports an accessibility
/// element count of zero throughout, because nothing in a unit-test process is
/// an assistive client — so there is no button on screen for a test in this
/// target to press. What is left is that the sheet's own methods are exactly
/// what the trash and the two alert buttons call, and one screenshot showing the
/// control is rendered.
@MainActor
final class SavedCardConfirmationTests: XCTestCase {

    private let visa = "card_1"
    private let mastercard = "card_2"
    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    // MARK: - Pressing the trash

    /// The press must not delete anything on its own. A trash wired straight to
    /// the server is one mis-tap from a card the shopper never agreed to lose.
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

    /// The half that makes the confirmation worth having. Without it, an alert
    /// whose Cancel deleted the card anyway would pass every test above.
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

    /// The alert's own dismissal writes `false` through the presentation
    /// binding, which is a second way for the prompt to close. It must not leave
    /// a card armed for whatever the next confirmation answers.
    func testConfirmingWithNothingPendingDoesNothing() async throws {
        let (model, transport) = try await makeSheet()

        model.confirmRemoval()

        XCTAssertNil(model.removalTask)
        let sent = await transport.sent
        XCTAssertFalse(sent.contains { $0.httpMethod == "DELETE" })
        XCTAssertEqual(model.form.savedCards.count, 2)
    }

    // MARK: - Whether the trash is offered at all

    /// The picker is what decides this, and it decides twice: the session has to
    /// allow removal, and no payment may be in flight.
    ///
    /// Asserted on what is drawn, because that is the only observable there is.
    /// A row with a trash on it cannot render identically to one without, so a
    /// picker that matches the no-removal baseline pixel for pixel did not draw
    /// the control.
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

    /// One picker, drawn, as PNG bytes.
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

    private func host(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        windows.append(window)

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return window
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
