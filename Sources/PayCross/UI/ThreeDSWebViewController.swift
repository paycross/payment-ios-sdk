#if os(iOS)
import UIKit
import WebKit
import PayCrossCore

/// Hosts a 3DS step in a `WKWebView`.
///
/// `WKWebView` rather than `SFSafariViewController` or `ASWebAuthenticationSession`:
/// both of those run out of process, so the SDK cannot observe navigation to
/// decide when the step finished, and the fingerprint step must run *invisibly* —
/// neither of them can do that at all.
final class ThreeDSWebViewController: UIViewController {

    private let action: ThreeDSAction
    private let onFinish: (ThreeDSOutcome) -> Void
    /// Set for a challenge only. A challenge is added over the whole payment
    /// sheet, toolbar included, so it has to carry the way out itself.
    private let onCancel: (() -> Void)?
    private var hasFinished = false
    private var webView: WKWebView!

    /// A challenge is the only step the shopper sees, and the only one that
    /// needs chrome of its own.
    private var isChallenge: Bool { onCancel != nil }

    init(
        action: ThreeDSAction,
        onCancel: (() -> Void)? = nil,
        onFinish: @escaping (ThreeDSOutcome) -> Void
    ) {
        self.action = action
        self.onCancel = onCancel
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let configuration = WKWebViewConfiguration()
        // Non-persistent: nothing from the ACS session is written to disk, which
        // is the iOS counterpart of Android's LOAD_NO_CACHE plus file access off.
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        view.addSubview(webView)

        if isChallenge {
            // Opaque, or the sheet it covers shows through above the bar.
            view.backgroundColor = .systemBackground
            // Confines VoiceOver to the challenge. Without it the card form
            // underneath is still read out, and can still be operated.
            view.accessibilityViewIsModal = true
            installCancelBar()
        } else {
            // Fingerprint: full bleed, and sent to the back by the presenter.
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        load()
    }

    /// Gives the challenge a Cancel of its own, *above* the ACS page rather than
    /// floating over it, so nothing the issuer draws is obscured.
    private func installCancelBar() {
        let bar = UINavigationBar()
        // A standalone bar is transparent by default, which would let the ACS
        // page scroll up behind the button.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance

        let cancel = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped)
        )
        cancel.accessibilityIdentifier = "threeDSCancel"
        // Titled like the sheet it stands in for, so answering the bank still
        // looks like the same payment rather than a screen of its own.
        let item = UINavigationItem(title: "Payment")
        item.leftBarButtonItem = cancel
        bar.items = [item]

        bar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Target/action rather than a `UIAction`: `UIActionHandler` is `@Sendable`,
    /// and the sheet's cancel closure is main-actor isolated, not sendable.
    @objc private func cancelTapped() {
        onCancel?()
    }

    private func load() {
        guard let url = URL(string: action.url) else {
            return finish(.failed)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if action.isPost {
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = Data(ThreeDSNavigation.encodeFormBody(action.data).utf8)
        }

        webView.load(request)
    }

    private func finish(_ outcome: ThreeDSOutcome) {
        // Navigation can fire more than once; the flow must only be told once.
        guard !hasFinished else { return }
        hasFinished = true
        onFinish(outcome)
    }
}

extension ThreeDSWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        if ThreeDSNavigation.isCompletionURL(url, actionURL: action.url) {
            finish(.completed)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failed)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failed)
    }

    /// No custom challenge handling: falling through to `.performDefaultHandling`
    /// keeps ATS and the system trust evaluation in charge, so an invalid
    /// certificate fails the load rather than being waved through. Android has to
    /// say this explicitly by calling handler.cancel(); on iOS it is the default,
    /// and the danger would be overriding it.
    ///
    /// `completionHandler` must be `@MainActor` to exactly match WebKit's
    /// imported requirement (its header marks the block `WK_SWIFT_UI_ACTOR`).
    /// Without it this override only *nearly* matched the protocol requirement
    /// and silently never ran — per WKNavigationDelegate's own doc comment, an
    /// unimplemented method makes every challenge reject the protection space
    /// instead of falling through to `.performDefaultHandling`.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Presents 3DS steps for the payment sheet.
///
/// The fingerprint step is invisible to the shopper but is rendered full size and
/// fully opaque *underneath* the processing overlay, rather than at zero alpha or
/// one point square: WebKit throttles rendering of content it believes is not
/// visible, and a throttled fingerprint silently fails to post its device data.
@MainActor
final class WebKitThreeDSPresenter: ThreeDSPresenting {

    private weak var host: UIViewController?
    /// Runs the sheet's own two-step cancel confirmation.
    ///
    /// A challenge is added at `host.view.bounds`, so it paints over the sheet's
    /// toolbar and the only Cancel the shopper has. The request therefore has to
    /// be able to come from the challenge's own bar, and it goes to the same
    /// confirmation rather than abandoning the payment on one tap.
    private let onCancelRequested: () -> Void
    /// The step currently on screen, with the continuation waiting on it.
    ///
    /// Held together so teardown can never happen without resuming. An earlier
    /// version kept only the controller, so `dismiss()` deallocated the closure
    /// holding the continuation without resuming it — a leaked continuation on
    /// *every* 3DS payment, which also left the runner and its API client
    /// retained forever because `presentationTask` never completed.
    private var active: (
        controller: ThreeDSWebViewController,
        continuation: CheckedContinuation<ThreeDSOutcome, Never>
    )?

    init(host: UIViewController, onCancelRequested: @escaping () -> Void) {
        self.host = host
        self.onCancelRequested = onCancelRequested
    }

    /// Unreachable under current wiring — the sheet model retains the presenter
    /// for the life of the sheet, and every teardown path goes through
    /// `resolve(_:)`. Defense-in-depth for a refactor that changes retention:
    /// if a deallocated presenter still held a step, its continuation would
    /// otherwise be dropped without resuming and the runner would await forever.
    deinit {
        active?.continuation.resume(returning: .failed)
    }

    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome {
        // A fingerprint is normally followed by a challenge. Resolve and tear
        // down the previous step first, or its web view stays in the hierarchy
        // for the life of the sheet and its continuation is orphaned.
        resolve(.failed)

        return await withCheckedContinuation { continuation in
            guard let host else {
                return continuation.resume(returning: .failed)
            }

            let controller = ThreeDSWebViewController(
                action: step.action,
                onCancel: step.isChallenge ? onCancelRequested : nil
            ) { [weak self] outcome in
                self?.resolve(outcome)
            }
            active = (controller, continuation)

            host.addChild(controller)
            controller.view.frame = host.view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.addSubview(controller.view)
            controller.didMove(toParent: host)

            if !step.isChallenge {
                // Fingerprint: below everything the shopper can see, but rendered.
                host.view.sendSubviewToBack(controller.view)
            }
        }
    }

    func dismiss() async {
        resolve(.failed)
    }

    /// Tears the step down and resumes whoever is waiting, exactly once.
    ///
    /// Clearing `active` before resuming makes a second call a no-op, so the
    /// controller's own completion and a reducer-driven `dismiss()` racing each
    /// other cannot double-resume.
    private func resolve(_ outcome: ThreeDSOutcome) {
        guard let (controller, continuation) = active else { return }
        active = nil

        controller.willMove(toParent: nil)
        // The cancel bar is part of the controller's own view, so it can never
        // outlive the step it belongs to.
        controller.view.removeFromSuperview()
        controller.removeFromParent()

        continuation.resume(returning: outcome)
    }
}
#endif
