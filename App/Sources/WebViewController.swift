import UIKit
import WebKit

/// Shows the bundled `index.html` and bridges the browser features it relies on
/// (downloads, popups, WhatsApp links, alert/confirm/prompt) to their iOS equivalents.
final class WebViewController: UIViewController {
    /// The page is loaded under this origin so localStorage, the clipboard API and Firebase
    /// see a secure https context instead of an opaque file:// one.
    static let origin = URL(string: "https://localhost/")!

    private var webView: WKWebView!
    private var pageIsDark = true
    // window.open() returns null here, so the page falls back to location.href with the same URL;
    // this remembers the last external URL to avoid opening WhatsApp twice.
    private var lastExternal: (url: URL, time: Date)?

    override var preferredStatusBarStyle: UIStatusBarStyle { pageIsDark ? .lightContent : .darkContent }

    override func loadView() {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Bridge.downloads, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Bridge.layout, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let handler = WeakMessageHandler(self)
        controller.add(handler, name: Bridge.downloadHandler)
        controller.add(handler, name: Bridge.themeHandler)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #if DEBUG
        webView.isInspectable = true
        #endif

        let root = UIView()
        root.backgroundColor = UIColor(named: "LaunchBackground")
        root.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // The page does not pad for the status bar, so it starts below it; the bottom runs to the
        // edge and the page's own env(safe-area-inset-bottom) clears the home indicator.
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadPage()
    }

    private func loadPage() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("index.html no está en el paquete de la app")
            return
        }
        webView.loadHTMLString(html, baseURL: Self.origin)
    }

    private func openExternally(_ url: URL) {
        if let last = lastExternal, last.url == url, Date().timeIntervalSince(last.time) < 2 { return }
        lastExternal = (url, Date())
        UIApplication.shared.open(url)
    }

    private func isInternal(_ url: URL) -> Bool {
        if ["about", "blob", "data"].contains(url.scheme ?? "") { return true }
        return url.host == Self.origin.host
    }

    private var presenter: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    // MARK: - Messages from the page

    fileprivate func receive(_ message: WKScriptMessage) {
        switch message.name {
        case Bridge.downloadHandler:
            guard let body = message.body as? [String: Any],
                  let base64 = body["datos"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            share(data, named: body["nombre"] as? String ?? "archivo")
        case Bridge.themeHandler:
            guard let css = message.body as? String, let color = UIColor(cssRGB: css) else { return }
            view.backgroundColor = color
            pageIsDark = color.isDark
            setNeedsStatusBarAppearanceUpdate()
        default:
            break
        }
    }

    private func share(_ data: Data, named name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exportaciones", isDirectory: true)
        let file = folder.appendingPathComponent(safeName.isEmpty ? "archivo" : safeName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            showMessage("No se pudo guardar el archivo: \(error.localizedDescription)")
            return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        presenter.present(sheet, animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}

// MARK: - Navigation

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        // Firebase may load helper iframes; only top-level navigations leave the app.
        if isInternal(url) || action.targetFrame?.isMainFrame == false {
            return decisionHandler(.allow)
        }
        openExternally(url)
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPage()
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, !isInternal(url) { openExternally(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        presenter.present(alert, animated: true)
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle with the controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebViewController?
    init(_ target: WebViewController) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}
