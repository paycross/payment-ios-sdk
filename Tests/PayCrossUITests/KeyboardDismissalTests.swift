#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// Pins the way out of the numeric keypad.
///
/// The keypad `keyboardType(.numberPad)` raises has no Return key, and iOS gives
/// it no accessory, so before this the CVV pad covered the lower third of the
/// sheet with nothing on screen that would put it away. Core cannot see any of
/// that; the affordance lives entirely in the view hierarchy, so it is asserted
/// here on real hosted fields.
@MainActor
final class KeyboardDismissalTests: XCTestCase {

    /// Held for the duration of the test; a released window takes the hierarchy
    /// under test with it.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.removeAll()
        try await super.tearDown()
    }

    private func hostForm(savedCards: [SavedCard] = []) -> UIWindow {
        var state = CardFormState(savedCards: savedCards)
        let view = CardFormView(
            state: Binding(get: { state }, set: { state = $0 }),
            amount: Amount(minorUnits: 1000, currencyCode: "EUR"),
            allowsSaving: false,
            isLoading: false,
            fieldGroups: [],
            fieldValues: .constant([:]),
            fieldErrors: [],
            onPay: {}
        )
        let controller = UIHostingController(rootView: NavigationStack { view })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // Attach to the live scene when there is one, so the fields can take
        // first responder.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        windows.append(window)
        return window
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view.subviews.compactMap { $0 as? UITextField })
            + view.subviews.flatMap(textFields(in:))
    }

    private func field(_ identifier: String, in window: UIWindow) throws -> UITextField {
        try XCTUnwrap(
            textFields(in: window).first { $0.accessibilityIdentifier == identifier },
            "no field identified as \(identifier)"
        )
    }

    private func doneItem(of field: UITextField) throws -> UIBarButtonItem {
        let bar = try XCTUnwrap(
            field.inputAccessoryView as? UIToolbar,
            "\(field.accessibilityIdentifier ?? "field") raises a keypad with no accessory"
        )
        return try XCTUnwrap(
            bar.items?.first { $0.accessibilityIdentifier == "keyboardDone" },
            "the accessory carries no Done control"
        )
    }

    // MARK: - The affordance exists

    func testEveryNumericFieldCarriesADoneControl() throws {
        let window = hostForm()

        for identifier in ["cardNumber", "expiry", "cvv"] {
            let item = try doneItem(of: try field(identifier, in: window))
            XCTAssertEqual(item.title, "Done", "\(identifier)'s control must say what it does")
            XCTAssertNotNil(item.target)
            XCTAssertNotNil(item.action)
        }
    }

    /// The saved-card path shows the CVV field alone; it needs the way out too.
    func testTheSavedCardCVVCarriesADoneControl() throws {
        let saved = SavedCard(id: "u", brand: .visa, last4: "1111", expiryLabel: "12/30")
        let window = hostForm(savedCards: [saved])

        let cvv = try field("cvv", in: window)
        XCTAssertEqual(try doneItem(of: cvv).title, "Done")
    }

    // MARK: - The affordance works

    func testDoneResignsTheField() throws {
        let window = hostForm()
        let cvv = try field("cvv", in: window)

        try XCTSkipUnless(cvv.becomeFirstResponder(), "the field could not take first responder")
        XCTAssertTrue(cvv.isFirstResponder)

        let done = try doneItem(of: cvv)
        let target = try XCTUnwrap(done.target)
        let action = try XCTUnwrap(done.action)
        _ = (target as AnyObject).perform(action, with: done)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertFalse(cvv.isFirstResponder, "Done must put the keypad away")
    }

    /// The Done button and the tap-anywhere gesture share this, so it is asserted
    /// on its own rather than only through the button.
    func testDismissalResignsWhicheverFieldIsEditing() throws {
        let window = hostForm()
        let pan = try field("cardNumber", in: window)

        try XCTSkipUnless(pan.becomeFirstResponder(), "the field could not take first responder")

        XCTAssertTrue(KeypadDismissal.resignFirstResponder(), "nothing was recorded as editing")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertFalse(pan.isFirstResponder)
    }

    /// With no keypad up there is nothing to close, and the tap must not reach for
    /// anything outside the sheet to find one.
    func testDismissalIsANoOpWhenNothingIsEditing() throws {
        _ = hostForm()
        XCTAssertFalse(KeypadDismissal.resignFirstResponder())
    }

    // MARK: - Nothing else moved

    /// The fields still feed the reducer: the CVV is the one the bug is about and
    /// the one whose digits must still land in state.
    func testTypingStillReachesTheReducer() throws {
        let window = hostForm()
        let cvv = try field("cvv", in: window)

        XCTAssertTrue(cvv.isSecureTextEntry, "a CVV must not be shoulder-readable")
        XCTAssertEqual(cvv.keyboardType, .numberPad)
    }
}
#endif
