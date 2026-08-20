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
    private var hasFinished = false
    private var webView: WKWebView!

    init(action: ThreeDSAction, onFinish: @escaping (ThreeDSOutcome) -> Void) {
        self.action = action
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
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

        load()
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

    init(host: UIViewController) {
        self.host = host
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

            let controller = ThreeDSWebViewController(action: step.action) { [weak self] outcome in
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
        controller.view.removeFromSuperview()
        controller.removeFromParent()

        continuation.resume(returning: outcome)
    }
}
#endif
