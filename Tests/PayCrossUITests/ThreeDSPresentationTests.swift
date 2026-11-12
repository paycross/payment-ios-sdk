#if os(iOS)
import XCTest
import UIKit
import WebKit
@testable import PayCross
@testable import PayCrossCore

@MainActor
final class ThreeDSPresentationTests: XCTestCase {

    private static let hostSize = CGSize(width: 390, height: 844)

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

    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

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
        XCTAssertEqual(cancel.accessibilityIdentifier, PayCrossTestIdentifiers.threeDSCancel.rawValue)

        XCTAssertEqual(
            bar.superview?.accessibilityIdentifier, PayCrossTestIdentifiers.threeDS.rawValue
        )

        let point = bar.convert(CGPoint(x: 58, y: bar.bounds.midY), to: host.view)
        let hit = try XCTUnwrap(host.view.hitTest(point, with: nil), "nothing is hit-testable")
        XCTAssertTrue(
            hit.isDescendant(of: bar),
            "a tap where the challenge's Cancel is drawn must reach it, not \(type(of: hit))"
        )

        let target = try XCTUnwrap(cancel.target as? NSObject)
        let action = try XCTUnwrap(cancel.action)
        target.perform(action)
        XCTAssertEqual(cancels.value, 1, "the cancel control must run the sheet's own cancel")

        await presenter.dismiss()
        _ = await task.value
    }

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

    func testPresentingAChallengePutsTheFormsKeypadAway() async throws {
        try await assertKeypadIsPutAway(isChallenge: true)
    }

    func testPresentingAFingerprintPutsTheFormsKeypadAway() async throws {
        try await assertKeypadIsPutAway(isChallenge: false)
    }

    private func assertKeypadIsPutAway(isChallenge: Bool) async throws {
        let host = makeHost()
        host.view.window?.makeKeyAndVisible()

        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        field.accessibilityIdentifier = PayCrossTestIdentifiers.cvv.rawValue
        host.view.addSubview(field)
        try XCTSkipUnless(field.becomeFirstResponder(), "the stand-in field could not take focus")

        let presenter = WebKitThreeDSPresenter(host: host) {}
        let task = Task { await presenter.present(step(isChallenge: isChallenge)) }
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

private final class CancelCounter {
    var value = 0
}
#endif
