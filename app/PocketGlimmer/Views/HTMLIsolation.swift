import Foundation
import WebKit

/// Renders model-supplied HTML/SVG with no way to reach the network or the app.
///
/// Layers, each sufficient for its own class of leak:
/// 1. Content rules compiled and installed before the first load block every subresource type and child frames,
///    so images, fonts, CSS, media, fetches and iframes never start a request.
/// 2. The page carries a content-security-policy (`RichReply.page`).
/// 3. Page JavaScript is off, there is no script message handler, the data store is non-persistent and the
///    document has no base URL, so there is no file or origin access.
/// 4. The navigation delegate cancels everything except the single load the controller started itself.
@MainActor
final class IsolatedHTMLController: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let ruleListIdentifier = "offllama.html.block-all.v1"
    static let blockRules = """
    [{"trigger":{"url-filter":".*","resource-type":["image","style-sheet","font","script","raw","svg-document","media","popup","ping","fetch","websocket","other"]},"action":{"type":"block"}},
     {"trigger":{"url-filter":".*","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}]
    """

    private static var compiled: WKContentRuleList?

    static func ruleList(store: WKContentRuleListStore? = nil) async throws -> WKContentRuleList {
        if let compiled { return compiled }
        guard let store = store ?? WKContentRuleListStore.default() else { throw CocoaError(.featureUnsupported) }
        let existing: WKContentRuleList? = try? await store.contentRuleList(forIdentifier: ruleListIdentifier)
        let made: WKContentRuleList? = existing == nil
            ? try await store.compileContentRuleList(forIdentifier: ruleListIdentifier, encodedContentRuleList: blockRules)
            : nil
        guard let list = existing ?? made else { throw CocoaError(.featureUnsupported) }
        compiled = list
        return list
    }

    let webView: WKWebView
    var onContentHeight: ((CGFloat) -> Void)?
    var onCancelledNavigation: ((URL?) -> Void)?
    private(set) var loadedPage: String?
    private var permitInitialLoad = false

    init(rules: WKContentRuleList) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(rules)
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = false
        configuration.dataDetectorTypes = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        #endif
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        if #available(iOS 16.4, macOS 13.3, *) { webView.isInspectable = false }
    }

    /// Loads once per distinct page; repeated calls with the same page do nothing.
    func load(page: String) {
        guard page != loadedPage else { return }
        loadedPage = page
        permitInitialLoad = true
        webView.loadHTMLString(page, baseURL: nil)
    }

    func measureContent() {
        webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { [weak self] value, _ in
            if let h = value as? Double { self?.onContentHeight?(CGFloat(h)) }
            else if let h = value as? Int { self?.onContentHeight?(CGFloat(h)) }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isOwnLoad = permitInitialLoad && navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.request.url?.absoluteString == "about:blank"
        if isOwnLoad {
            permitInitialLoad = false
            decisionHandler(.allow)
        } else {
            onCancelledNavigation?(navigationAction.request.url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { measureContent() }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        onCancelledNavigation?(navigationAction.request.url)
        return nil
    }
}
