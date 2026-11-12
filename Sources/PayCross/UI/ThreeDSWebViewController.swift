#if os(iOS)
import UIKit
import WebKit
import PayCrossCore

// WKWebView, not SFSafariViewController or ASWebAuthenticationSession, which run out
// of process: the SDK could not observe navigation or run the fingerprint step invisibly.
final class ThreeDSWebViewController: UIViewController {

    private let action: ThreeDSAction
    private let onFinish: (ThreeDSOutcome) -> Void
    // A challenge covers the sheet's toolbar, so it carries its own way out.
    private let onCancel: (() -> Void)?
    private let surfaceColor: UIColor?
    private var hasFinished = false
    private var webView: WKWebView!

    private var isChallenge: Bool { onCancel != nil }

    init(
        action: ThreeDSAction,
        onCancel: (() -> Void)? = nil,
        surfaceColor: UIColor? = nil,
        onFinish: @escaping (ThreeDSOutcome) -> Void
    ) {
        self.action = action
        self.onCancel = onCancel
        self.surfaceColor = surfaceColor
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
        // Non-persistent, so no 3DS session data is written to disk.
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        view.addSubview(webView)

        if isChallenge {
            // Opaque, or the sheet underneath shows through the bar.
            view.backgroundColor = surfaceColor ?? .systemBackground
            // Without this, VoiceOver still reads and operates the card form underneath.
            view.accessibilityViewIsModal = true
            view.accessibilityIdentifier = PayCrossTestIdentifiers.threeDS.rawValue
            installCancelBar()
        } else {
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        load()
    }

    private func installCancelBar() {
        let bar = UINavigationBar()
        // A standalone bar is transparent by default, so the page would show through it.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance

        let cancel = UIBarButtonItem(
            title: L("paycross_cancel", "Cancel"), style: .plain, target: self, action: #selector(cancelTapped)
        )
        cancel.accessibilityIdentifier = PayCrossTestIdentifiers.threeDSCancel.rawValue
        let item = UINavigationItem(title: L("paycross_payment", "Payment"))
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

    // Target/action, not UIAction: UIActionHandler is @Sendable, and the cancel closure is
    // main-actor isolated and not Sendable.
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
        // WebKit can report navigation more than once; the flow must be told only once.
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

    // Default handling keeps ATS and system trust evaluation in charge, so an invalid
    // certificate fails the load.
    // The completion handler must be @MainActor to match WebKit's imported signature;
    // otherwise this override silently never runs, and WebKit rejects every challenge.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}

// The fingerprint step renders full size and opaque under the overlay: WebKit throttles
// content it believes is hidden, and a throttled fingerprint never posts its device data.
@MainActor
final class WebKitThreeDSPresenter: ThreeDSPresenting {

    private weak var host: UIViewController?
    private let surfaceColor: UIColor?
    // A challenge covers the sheet's toolbar, so its cancel must reach the sheet's two-step
    // confirmation.
    private let onCancelRequested: () -> Void
    // Held with the continuation, so teardown always resumes it.
    private var active: (
        controller: ThreeDSWebViewController,
        continuation: CheckedContinuation<ThreeDSOutcome, Never>
    )?

    init(
        host: UIViewController,
        surfaceColor: UIColor? = nil,
        onCancelRequested: @escaping () -> Void
    ) {
        self.host = host
        self.surfaceColor = surfaceColor
        self.onCancelRequested = onCancelRequested
    }

    // A continuation dropped without resuming leaves the runner awaiting forever.
    deinit {
        active?.continuation.resume(returning: .failed)
    }

    func present(_ step: ThreeDSStep) async -> ThreeDSOutcome {
        // A step still on screen must be torn down first, or its continuation is orphaned.
        resolve(.failed)

        return await withCheckedContinuation { continuation in
            guard let host else {
                return continuation.resume(returning: .failed)
            }

            // The CVV field keeps first responder, and its keypad would cover the challenge's
            // buttons. Scoped to the sheet, so a host field edited behind it is left alone.
            host.view.endEditing(true)

            let controller = ThreeDSWebViewController(
                action: step.action,
                onCancel: step.isChallenge ? onCancelRequested : nil,
                surfaceColor: surfaceColor
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
                host.view.sendSubviewToBack(controller.view)
            }
        }
    }

    func dismiss() async {
        resolve(.failed)
    }

    // Active is cleared before resuming, so a second call from a racing completion or dismiss
    // cannot resume twice.
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
