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
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
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
    private var current: ThreeDSWebViewController?

    init(host: UIViewController) {
        self.host = host
    }

    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome {
        await withCheckedContinuation { continuation in
            guard let host else {
                return continuation.resume(returning: .failed)
            }

            let controller = ThreeDSWebViewController(action: step.action) { outcome in
                continuation.resume(returning: outcome)
            }
            self.current = controller

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
        guard let controller = current else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        current = nil
    }
}
#endif
