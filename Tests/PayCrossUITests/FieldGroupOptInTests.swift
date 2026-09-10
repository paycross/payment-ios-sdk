#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// A group the merchant offers rather than requires.
///
/// Two halves, in one file because they are the same claim asked twice. The
/// render says a declined group draws its offer and nothing else; the model
/// says it is not validated and not submitted. Neither half is worth much
/// alone: a group hidden but still validated blocks a payment for a reason
/// nothing on screen explains, and one skipped but still drawn asks the shopper
/// for an address that is thrown away.
@MainActor
final class FieldGroupOptInTests: XCTestCase {

    private let host = ViewHost()

    override func setUp() async throws {
        try await super.setUp()
        SheetLanguage.reset()
    }

    override func tearDown() async throws {
        host.release()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// The shipping group as the backend marks it: the flag beside the labels,
    /// and fields the merchant made required.
    private let shipping = FieldGroup(
        key: "shipping_address",
        label: "Shipping Address",
        labels: ["en": "Shipping Address", "fr": "Adresse de livraison"],
        optIn: true,
        fields: [
            FieldDefinition(
                name: "line1",
                type: "text",
                label: "Address line 1",
                placeholder: "SHIPPING LINE ONE",
                required: true
            )
        ]
    )

    /// The same group without the flag, which is every group the SDK has ever
    /// drawn.
    private let mandatory = FieldGroup(
        key: "shipping_address",
        label: "Shipping Address",
        labels: ["en": "Shipping Address", "fr": "Adresse de livraison"],
        fields: [
            FieldDefinition(
                name: "line1",
                type: "text",
                label: "Address line 1",
                placeholder: "SHIPPING LINE ONE",
                required: true
            )
        ]
    )

    /// An opt-in group whose only per-language string is its own heading, so a
    /// render that moves with the language can only have moved because the
    /// toggle's caption did.
    private let captionOnly = FieldGroup(
        key: "shipping_address",
        label: "Shipping Address",
        labels: ["en": "Shipping Address", "fr": "Adresse de livraison"],
        optIn: true,
        fields: [FieldDefinition(name: "line1", type: "text", label: "Line 1")]
    )

    private func form(_ group: FieldGroup, optedIn: Set<String>, language: String = "en") -> UIWindow {
        var state = CardFormState()
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: false,
            fieldGroups: [group],
            fieldValues: .constant([:]),
            optedInGroups: .constant(optedIn),
            fieldErrors: [],
            language: language,
            onPay: {}
        )
        return host(NavigationStack { view })
    }

    /// Every `UISwitch` under a view. A SwiftUI `Toggle` really is one, measured
    /// on the simulator, which is the only thing about this sheet's controls a
    /// test bundle can count: SwiftUI's accessibility tree is not built here.
    private func switches(in view: UIView) -> [UISwitch] {
        (view.subviews.compactMap { $0 as? UISwitch }) + view.subviews.flatMap(switches(in:))
    }

    private func placeholders(in window: UIWindow) -> [String] {
        textFields(in: window).compactMap { $0.placeholder ?? $0.attributedPlaceholder?.string }
    }

    // MARK: - What is drawn

    /// The control has to exist before anything else here means anything.
    func testAnOptInGroupAddsASwitchAndAMandatoryOneDoesNot() {
        XCTAssertEqual(switches(in: form(shipping, optedIn: [])).count, 1)
        XCTAssertEqual(
            switches(in: form(mandatory, optedIn: [])).count, 0,
            "a group nobody marked opt-in grew a toggle it never had"
        )
    }

    /// The bug as filed: required shipping fields with no way to decline them.
    func testADeclinedGroupDrawsItsOfferAndNoFields() {
        let window = form(shipping, optedIn: [])
        XCTAssertEqual(switches(in: window).count, 1, "the offer itself must stay on screen")
        XCTAssertFalse(
            placeholders(in: window).contains("SHIPPING LINE ONE"),
            "a declined group is still asking for an address"
        )
    }

    func testATickedGroupDrawsItsFields() {
        XCTAssertTrue(
            placeholders(in: form(shipping, optedIn: ["shipping_address"]))
                .contains("SHIPPING LINE ONE")
        )
    }

    /// The card fields come back in the same read, so an empty list would mean
    /// the read stopped working rather than that the group went away.
    func testTheReadItselfWorks() {
        XCTAssertTrue(
            placeholders(in: form(shipping, optedIn: [])).contains("NAME ON CARD"),
            "no placeholder could be read at all; the assertions above prove nothing"
        )
    }

    /// Without the flag nothing moves: the same group draws the same fields it
    /// always did, whatever the set holds.
    func testAGroupWithoutTheFlagIsDrawnExactlyAsBefore() {
        XCTAssertTrue(
            placeholders(in: form(mandatory, optedIn: [])).contains("SHIPPING LINE ONE")
        )
    }

    /// The toggle is captioned by the group's own heading, which the backend
    /// translates. An SDK string would be our words for the merchant's group.
    func testTheToggleIsCaptionedInTheSheetsLanguage() throws {
        XCTAssertGreaterThan(
            try differingPixels(
                render(captionOnly, "en"), render(captionOnly, "fr")
            ),
            0,
            "the French sheet drew the same caption on the toggle as the English one"
        )
    }

    // MARK: - What is validated and what is sent

    func testADeclinedGroupIsNotValidatedAndIsNotSubmitted() async throws {
        let (model, transport) = try await sheet()
        XCTAssertEqual(model.optedInGroups, [], "an opt-in group must arrive unticked")

        payWithACard(model)

        XCTAssertEqual(
            model.fieldErrors, [],
            "a shopper who declined the shipping group was still blocked by its required fields"
        )
        let body = try await submittedBody(transport, model)
        let groups = body["field_groups"] as? [String: Any]
        XCTAssertNil(
            groups?["shipping_address"],
            "the declined group reached the wire; an empty object is not the same as not being asked"
        )
        XCTAssertNotNil(groups?["billing_address"], "the mandatory group was dropped too")
        model.cancel()
    }

    func testATickedGroupIsValidatedLikeAnyOther() async throws {
        let (model, _) = try await sheet()
        model.optedInGroups = ["shipping_address"]

        payWithACard(model)

        XCTAssertEqual(model.fieldErrors.map(\.fieldName), ["line1"])
        XCTAssertEqual(model.fieldErrors.first?.groupKey, "shipping_address")
        XCTAssertFalse(model.isLoading, "a failed validation must not start a payment")
    }

    func testATickedGroupIsSubmittedWithItsValues() async throws {
        let (model, transport) = try await sheet()
        model.optedInGroups = ["shipping_address"]
        model.fieldValues["shipping_address"] = ["line1": "1 Rue de Rivoli"]

        payWithACard(model)

        XCTAssertEqual(model.fieldErrors, [])
        let body = try await submittedBody(transport, model)
        let groups = try XCTUnwrap(body["field_groups"] as? [String: Any])
        let shipped = try XCTUnwrap(groups["shipping_address"] as? [String: Any])
        XCTAssertEqual(shipped["line1"] as? String, "1 Rue de Rivoli")
        model.cancel()
    }

    /// A value the merchant prefilled is kept in state while the group is off,
    /// so ticking it back on restores the address instead of clearing it. It
    /// still may not be sent.
    func testAPrefilledDeclinedGroupIsHeldButNotSent() async throws {
        let (model, transport) = try await sheet()
        model.fieldValues["shipping_address"] = ["line1": "1 Rue de Rivoli"]

        payWithACard(model)

        let body = try await submittedBody(transport, model)
        let groups = body["field_groups"] as? [String: Any]
        XCTAssertNil(groups?["shipping_address"])
        XCTAssertEqual(
            model.fieldValues["shipping_address"]?["line1"], "1 Rue de Rivoli",
            "the shopper's own typing was thrown away by declining the group"
        )
        model.cancel()
    }

    /// A shopper shown "Address line 1 is required" under the shipping group,
    /// who answers it by declining the group, has answered it. The row goes
    /// with the tick, so an error left in the list is one nothing on screen can
    /// show and nothing can clear.
    ///
    /// Nothing draws it today, which is the point: this is the assertion that
    /// stops an error summary or a scroll-to-first-error, added later, from
    /// putting a complaint about a declined group back in front of the shopper
    /// with no test going red.
    func testUntickingAGroupAfterAFailedSubmitTakesItsErrorsWithIt() async throws {
        let (model, _) = try await sheet()
        model.optedInGroups = ["shipping_address"]
        // The mandatory group fails too, so this can tell pruning the declined
        // group's errors apart from simply emptying the list.
        model.fieldValues["billing_address"] = [:]

        payWithACard(model)
        XCTAssertEqual(
            Set(model.fieldErrors.map(\.groupKey)), ["billing_address", "shipping_address"],
            "the fixture failed neither group or only one; this test would prove nothing"
        )

        model.optedInGroups = []

        // By group and field, not by message: both groups name a field `line1`
        // and label it "Address line 1", so the sentence alone cannot say which
        // of the two is still complaining.
        XCTAssertEqual(
            model.fieldErrors.map { "\($0.groupKey).\($0.fieldName)" },
            ["billing_address.line1"],
            "a complaint about a group the shopper declined outlived the untick"
        )
    }

    /// And the other direction leaves the mandatory groups alone: ticking a
    /// group is not a reason to forget what the shopper was already told.
    func testTickingAGroupKeepsTheErrorsAlreadyOnScreen() async throws {
        let (model, _) = try await sheet()
        model.fieldValues["billing_address"] = [:]

        payWithACard(model)
        XCTAssertEqual(model.fieldErrors.map(\.groupKey), ["billing_address"])

        model.optedInGroups = ["shipping_address"]

        XCTAssertEqual(model.fieldErrors.map(\.groupKey), ["billing_address"])
    }

    // MARK: - Plumbing

    private func render(_ group: FieldGroup, _ language: String) -> UIImage {
        let window = form(group, optedIn: [], language: language)
        // Longer than the shared settle, for the reason the language suite
        // gives: a layer read before the text has drawn compares two blank
        // forms and passes while proving nothing.
        host.settle(0.4)
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private func payWithACard(_ model: PaymentSheetModel) {
        CardFormReducer.reduce(state: &model.form, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &model.form, event: .expiryChanged("12/30"))
        CardFormReducer.reduce(state: &model.form, event: .cvvChanged("123"))
        CardFormReducer.reduce(state: &model.form, event: .nameChanged("A Shopper"))
        model.pay()
    }

    /// The submitted body, or a failed test.
    ///
    /// Polled to a deadline rather than simply awaited: a regression that stops
    /// the payment being submitted at all -- which is exactly what a declined
    /// group blocking validation would do -- must fail this test rather than
    /// hang it.
    private func submittedBody(
        _ transport: StubTransport, _ model: PaymentSheetModel
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(5)
        while await transport.sent.count < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // The second request, by index. The submission is followed by polls,
        // and `last` would read whichever of those happened to have landed.
        let sent = await transport.sent
        guard sent.count > 1 else {
            XCTFail(
                "the payment was never submitted; it was blocked by "
                    + model.fieldErrors.map(\.fieldName).description
            )
            return [:]
        }
        let submitted = try XCTUnwrap(sent[1].httpBody, "nothing was submitted")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: submitted) as? [String: Any])
    }

    private func sheet() async throws -> (PaymentSheetModel, StubTransport) {
        let transport = StubTransport(replies: [
            .init(body: Data(sessionJSON.utf8)),
            .init(body: Data(#"{"success":true,"transaction_id":"t1","status":"success"}"#.utf8))
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
        XCTAssertEqual(
            model.fieldGroups.map(\.key), ["billing_address", "shipping_address"],
            "the fixture session did not load"
        )
        return (model, transport)
    }

    /// A billing group the shopper cannot decline, prefilled so it never blocks
    /// the payment, and the shipping group the merchant marked opt-in.
    private let sessionJSON = """
    {
      "session_id": "sess_1",
      "status": "open",
      "data": {
        "field_groups": [
          {
            "key": "billing_address",
            "label": "Billing Address",
            "fields": [
              {
                "name": "line1", "type": "text", "label": "Address line 1",
                "required": true, "value": "10 Downing Street"
              }
            ]
          },
          {
            "key": "shipping_address",
            "label": "Shipping Address",
            "labels": { "en": "Shipping Address", "fr": "Adresse de livraison" },
            "opt_in": true,
            "fields": [
              { "name": "line1", "type": "text", "label": "Address line 1", "required": true }
            ]
          }
        ]
      }
    }
    """
}
#endif
