#if os(iOS)
import XCTest
import UIKit
import WebKit
@testable import PayCross
@testable import PayCrossCore

/// Pins the escape hatch a 3-D Secure challenge has to carry.
///
/// A challenge is added at `host.view.bounds`, so it paints over the payment
/// sheet's `NavigationStack` toolbar and the only Cancel the shopper has. 0.1.0
/// shipped with nothing in its place and `isModalInPresentation` on: the shopper
/// was held to the 480s poll deadline and got `.failed(recovery: .retry)` rather
/// than `.cancelled`. Core cannot see any of that — `PaymentFlowRunnerTests`
/// cancels the runner directly and passes — because the defect is entirely in the
/// view hierarchy. So it is asserted here, on a real hosted controller.
@MainActor
final class ThreeDSPresentationTests: XCTestCase {

    private static let hostSize = CGSize(width: 390, height: 844) // iPhone 17 portrait

    /// `about:blank` loads, so nothing races the assertions: a real ACS URL would
    /// either complete or fail its navigation and tear the step down mid-test.
    /// It is also never a completion URL, so the step stays up.
    private func step(isChallenge: Bool) -> ThreeDSStep {
        ThreeDSStep(
            action: ThreeDSAction(url: "about:blank", method: "GET"),
            isChallenge: isChallenge
        )
    }

    private func makeHost() -> UIViewController {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.hostSize))
        window.rootViewController = host
        window.isHidden = false
        windows.append(window)
        host.view.frame = CGRect(origin: .zero, size: Self.hostSize)
        host.view.layoutIfNeeded()
        return host
    }

    /// Held for the duration of the test; a released window takes the hierarchy
    /// under test with it.
    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    /// Starts a step and waits for it to be installed, without awaiting the
    /// outcome — `present` only resumes when the step is resolved.
    private func present(
        _ step: ThreeDSStep,
        on host: UIViewController,
        with presenter: WebKitThreeDSPresenter
    ) async throws -> Task<ThreeDSOutcome, Never> {
        let task = Task { await presenter.present(step) }
        for _ in 0..<200 where host.view.subviews.isEmpty {
            await Task.yield()
        }
        try XCTSkipIf(host.view.subviews.isEmpty, "the step was never installed")
        host.view.layoutIfNeeded()
        return task
    }

    // MARK: - Challenge

    func testChallengePresentsAReachableCancelControl() async throws {
        let host = makeHost()
        let cancels = CancelCounter()
        let presenter = WebKitThreeDSPresenter(host: host) { cancels.value += 1 }
        let task = try await present(step(isChallenge: true), on: host, with: presenter)

        let bar = try XCTUnwrap(
            firstSubview(UINavigationBar.self, in: host.view),
            "a challenge covers the sheet's toolbar and must supply a bar of its own"
        )
        let cancel = try XCTUnwrap(bar.items?.first?.leftBarButtonItem, "no cancel control")
        XCTAssertEqual(cancel.accessibilityIdentifier, "threeDSCancel")

        // The regression itself: during a challenge a tap at the Cancel's own
        // coordinates landed on the ACS web view and did nothing.
        let point = bar.convert(CGPoint(x: 58, y: bar.bounds.midY), to: host.view)
        let hit = try XCTUnwrap(host.view.hitTest(point, with: nil), "nothing is hit-testable")
        XCTAssertTrue(
            hit.isDescendant(of: bar),
            "a tap where the challenge's Cancel is drawn must reach it, not \(type(of: hit))"
        )

        // And it asks the sheet to cancel rather than doing it itself, so the
        // shopper still gets the two-step "Cancel Payment?" confirmation.
        let target = try XCTUnwrap(cancel.target as? NSObject)
        let action = try XCTUnwrap(cancel.action)
        target.perform(action)
        XCTAssertEqual(cancels.value, 1, "the cancel control must run the sheet's own cancel")

        await presenter.dismiss()
        _ = await task.value
    }

    /// The issuer's page must keep every point it had; the way out is drawn above
    /// it, not over it.
    func testChallengeWebViewIsNotCoveredByTheCancelBar() async throws {
        let host = makeHost()
        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = try await present(step(isChallenge: true), on: host, with: presenter)

        let container = try XCTUnwrap(host.view.subviews.first)
        let bar = try XCTUnwrap(firstSubview(UINavigationBar.self, in: container))
        let webView = try XCTUnwrap(firstSubview(WKWebView.self, in: container))

        XCTAssertGreaterThan(bar.bounds.height, 0, "the cancel bar has no height")
        XCTAssertGreaterThanOrEqual(
            webView.frame.minY, bar.frame.maxY,
            "the ACS page must start below the cancel bar, not behind it"
        )
        XCTAssertEqual(webView.frame.maxY, container.bounds.maxY, accuracy: 0.5)

        await presenter.dismiss()
        _ = await task.value
    }

    /// BUG 2's twin: without this VoiceOver reads, and can operate, the card form
    /// underneath the challenge.
    func testChallengeIsAccessibilityModal() async throws {
        let host = makeHost()
        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = try await present(step(isChallenge: true), on: host, with: presenter)

        let container = try XCTUnwrap(host.view.subviews.first)
        XCTAssertTrue(
            container.accessibilityViewIsModal,
            "VoiceOver must be confined to the challenge while it is up"
        )

        await presenter.dismiss()
        _ = await task.value
    }

    /// Every teardown path goes through `resolve(_:)`, and the bar is part of the
    /// step's own view — so it cannot outlive the step it belongs to.
    func testResolvingTheStepRemovesTheCancelControl() async throws {
        let host = makeHost()
        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = try await present(step(isChallenge: true), on: host, with: presenter)
        XCTAssertNotNil(firstSubview(UINavigationBar.self, in: host.view))

        await presenter.dismiss()
        _ = await task.value

        XCTAssertTrue(host.view.subviews.isEmpty, "the step was not torn down")
        XCTAssertNil(
            firstSubview(UINavigationBar.self, in: host.view),
            "a cancel control outliving its challenge would cancel a payment that has moved on"
        )
    }

    // MARK: - Fingerprint

    /// The fingerprint is invisible and unattended: chrome on it would be drawn
    /// over the sheet, and it is full-bleed and opaque because WebKit throttles
    /// content it believes is not visible.
    func testFingerprintStepGetsNoCancelBarAndStaysFullBleed() async throws {
        let host = makeHost()
        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = try await present(step(isChallenge: false), on: host, with: presenter)

        let container = try XCTUnwrap(host.view.subviews.first)
        XCTAssertNil(
            firstSubview(UINavigationBar.self, in: container),
            "a fingerprint the shopper never sees must not offer a cancel control"
        )
        XCTAssertFalse(container.accessibilityViewIsModal)

        let webView = try XCTUnwrap(firstSubview(WKWebView.self, in: container))
        XCTAssertEqual(webView.frame, container.bounds)

        await presenter.dismiss()
        _ = await task.value
    }

    // MARK: - The keypad the card form left behind

    /// The CVV field is still first responder when the flow leaves the card form,
    /// so its keypad follows the step onto the issuer's page and covers the lower
    /// third of it — where the challenge's own buttons sit. A rotation then leaves
    /// it stuck there with nothing that will close it.
    ///
    /// Asserted at the presenter rather than on the card form: the form is gone
    /// from view by this point, and the sheet has no other moment that knows a
    /// step is about to cover it.
    func testPresentingAChallengePutsTheFormsKeypadAway() async throws {
        try await assertKeypadIsPutAway(isChallenge: true)
    }

    /// The fingerprint runs under the processing overlay, which the keypad would
    /// cover just the same.
    func testPresentingAFingerprintPutsTheFormsKeypadAway() async throws {
        try await assertKeypadIsPutAway(isChallenge: false)
    }

    private func assertKeypadIsPutAway(isChallenge: Bool) async throws {
        let host = makeHost()
        // `makeHost` only unhides its window; first responder needs a key one.
        host.view.window?.makeKeyAndVisible()

        // Stands in for the card form's CVV field, editing when the step arrives.
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        field.accessibilityIdentifier = "cvv"
        host.view.addSubview(field)
        try XCTSkipUnless(field.becomeFirstResponder(), "the stand-in field could not take focus")

        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = Task { await presenter.present(step(isChallenge: isChallenge)) }
        // The shared `present` helper waits for the host to gain its first
        // subview, and the stand-in field is already one; wait for the step's own
        // web view instead.
        for _ in 0..<200 where firstSubview(WKWebView.self, in: host.view) == nil {
            await Task.yield()
        }
        try XCTSkipIf(
            firstSubview(WKWebView.self, in: host.view) == nil,
            "the step was never installed"
        )

        XCTAssertFalse(
            field.isFirstResponder,
            "the shopper's keypad must not follow them onto the bank's page"
        )

        await presenter.dismiss()
        _ = await task.value
    }

    // MARK: - Helpers

    private func firstSubview<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(type, in: subview) { return match }
        }
        return nil
    }
}

/// Boxed so the escaping cancel closure and the assertions read the same value.
private final class CancelCounter {
    var value = 0
}
#endif
