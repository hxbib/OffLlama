import AppKit
import WebKit

// Real-WebKit check of IsolatedHTMLController. Usage: html-isolation-check <server-port> <report-path>
// The companion shell script runs a local HTTP server and reads its request log; this binary only loads pages and
// reports what the controller did. Every hostile page points at http://127.0.0.1:<port>/<mode>-<case>.

let port = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "0"
let reportPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/dev/stdout"
var report: [String] = []
var failures = 0
func record(_ ok: Bool, _ name: String, _ detail: String = "") {
    report.append("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

func url(_ mode: String, _ name: String) -> String { "http://127.0.0.1:\(port)/\(mode)-\(name)" }

/// Each hostile construct requests a distinct path, so the server log says exactly which one escaped.
func hostileCases(_ mode: String) -> [(name: String, body: String)] {
    [
        ("img", "<img src=\"\(url(mode, "img"))\">"),
        ("srcset", "<img srcset=\"\(url(mode, "srcset")) 1x\">"),
        ("link-css", "<link rel=\"stylesheet\" href=\"\(url(mode, "link-css"))\">"),
        ("import-css", "<style>@import url(\(url(mode, "import-css")));</style>"),
        ("font", "<style>@font-face{font-family:x;src:url(\(url(mode, "font")))}p{font-family:x}</style><p>t</p>"),
        ("bg-image", "<div style=\"background-image:url(\(url(mode, "bg-image")));height:20px\">t</div>"),
        ("iframe", "<iframe src=\"\(url(mode, "iframe"))\"></iframe>"),
        ("object", "<object data=\"\(url(mode, "object"))\"></object>"),
        ("embed", "<embed src=\"\(url(mode, "embed"))\">"),
        ("video", "<video src=\"\(url(mode, "video"))\" preload=\"auto\"></video>"),
        ("audio", "<audio src=\"\(url(mode, "audio"))\" preload=\"auto\"></audio>"),
        ("prefetch", "<link rel=\"prefetch\" href=\"\(url(mode, "prefetch"))\"><link rel=\"preload\" as=\"image\" href=\"\(url(mode, "preload"))\">"),
        ("script", "<script src=\"\(url(mode, "script"))\"></script><script>new Image().src='\(url(mode, "script-inline"))'</script>"),
        ("svg-image", "<svg width=\"10\" height=\"10\"><image href=\"\(url(mode, "svg-image"))\" width=\"10\" height=\"10\"/></svg>"),
        ("svg-use", "<svg width=\"10\" height=\"10\"><use href=\"\(url(mode, "svg-use"))#a\"/></svg>"),
        ("svg-style-import", "<svg width=\"10\" height=\"10\"><style>@import url(\(url(mode, "svg-style-import")));</style></svg>"),
        ("base-relative", "<base href=\"http://127.0.0.1:\(port)/\"><img src=\"\(mode)-base-relative\">"),
        ("meta-refresh", "<meta http-equiv=\"refresh\" content=\"0;url=\(url(mode, "meta-refresh"))\">"),
        ("form-post", "<form id=\"f\" method=\"post\" action=\"\(url(mode, "form-post"))\"><input name=\"a\" value=\"1\"></form>"),
        ("anchor", "<a id=\"a\" href=\"\(url(mode, "anchor"))\">x</a>"),
        ("target-blank", "<a id=\"tb\" target=\"_blank\" href=\"\(url(mode, "target-blank"))\">x</a>"),
        ("tel", "<a id=\"tel\" href=\"tel:5551234567\">x</a>"),
    ]
}

let followUps = [
    "document.getElementById('f') && document.getElementById('f').submit();",
    "document.getElementById('a') && document.getElementById('a').click();",
    "document.getElementById('tb') && document.getElementById('tb').click();",
    "document.getElementById('tel') && document.getElementById('tel').click();",
]

@MainActor func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

@MainActor func eval(_ web: WKWebView, _ js: String) async -> Any? {
    await withCheckedContinuation { c in web.evaluateJavaScript(js) { v, _ in c.resume(returning: v) } }
}

@MainActor func run() async {
    // Control: a plain web view must hit the server, otherwise a quiet log proves nothing.
    let plain = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    plain.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    plain.loadHTMLString(hostileCases("control").filter { ["img", "link-css", "iframe", "font", "bg-image"].contains($0.name) }.map(\.body).joined(), baseURL: nil)
    await sleep(2.5)

    guard let rules = try? await IsolatedHTMLController.ruleList(store: WKContentRuleListStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("offllama-rules-\(getpid())"))) else {
        record(false, "content rule list compiles"); return
    }
    record(true, "content rule list compiles")

    for mode in ["raw", "page"] {
        var cancelled: [String] = []
        for c in hostileCases(mode) {
            let controller = IsolatedHTMLController(rules: rules)
            controller.webView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
            controller.onCancelledNavigation = { cancelled.append("\(c.name):\($0?.absoluteString ?? "nil")") }
            let source = "<p id=\"marker\">marker-\(c.name)</p>" + c.body
            let page = mode == "page"
                ? RichReply.page(for: EmbeddedMarkup(kind: .html, source: source))
                : "<!doctype html><html><body>\(source)</body></html>"
            controller.load(page: page)
            await sleep(0.8)
            for js in followUps { _ = await eval(controller.webView, js) }
            await sleep(0.6)
            let text = await eval(controller.webView, "document.body ? document.body.innerText : ''") as? String ?? ""
            if c.name != "meta-refresh" { record(text.contains("marker-\(c.name)"), "\(mode)/\(c.name): own content still renders") }
        }
        let navKinds = ["meta-refresh", "form-post", "anchor", "target-blank", "tel"]
        for k in navKinds {
            // With the page's CSP, form-action 'none' stops the submit before the delegate is asked; the raw pass covers the delegate.
            if mode == "page" && k == "form-post" { continue }
            record(cancelled.contains { $0.hasPrefix("\(k):") }, "\(mode)/\(k): navigation was cancelled by the delegate")
        }
    }

    // Ablation: same controller with a rule list that matches nothing. Subresources must now escape,
    // which shows the block rules, not the navigation delegate, are what stop them.
    let store = WKContentRuleListStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("offllama-null-rules-\(getpid())"))
    if let nullRules = try? await store?.compileContentRuleList(forIdentifier: "null", encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\"^never-matches$\"},\"action\":{\"type\":\"block\"}}]") {
        for name in ["img", "link-css", "font", "bg-image"] {
            let ablated = IsolatedHTMLController(rules: nullRules)
            ablated.webView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
            ablated.load(page: "<!doctype html><html><body>" + hostileCases("ablate").first { $0.name == name }!.body + "</body></html>")
            await sleep(1.2)
        }
    }

    let c = IsolatedHTMLController(rules: rules)
    c.webView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
    var finishes = 0
    var heights: [CGFloat] = []
    c.onContentHeight = { finishes += 1; heights.append($0) }
    let svg = EmbeddedMarkup(kind: .svg, source: "<svg viewBox=\"0 0 200 100\"><rect width=\"200\" height=\"100\"/><text x=\"5\" y=\"20\">bars</text></svg>")
    let page = RichReply.page(for: svg)
    c.load(page: page); await sleep(1.0)
    c.load(page: page); c.load(page: page); await sleep(0.8)
    record(finishes == 1, "same page is not reloaded by repeated updates", "finishes=\(finishes)")
    record((heights.first ?? 0) > 20 && (heights.first ?? 999) < 300, "content height (not viewport height) measured with page JavaScript off", "heights=\(heights)")
    c.load(page: RichReply.page(for: EmbeddedMarkup(kind: .html, source: "<p>other</p>"))); await sleep(0.8)
    record(finishes == 2, "a different page does load", "finishes=\(finishes)")

    let js = IsolatedHTMLController(rules: rules)
    js.webView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
    js.load(page: "<html><body><script>document.title='ran';document.body.setAttribute('data-ran','1')</script><p>x</p></body></html>")
    await sleep(0.8)
    record((await eval(js.webView, "document.title") as? String ?? "") != "ran", "page script does not run")
    record((await eval(js.webView, "document.body.getAttribute('data-ran')") as? String) == nil, "page script cannot mutate the document")
    record((await eval(js.webView, "typeof window.webkit === 'undefined' || !window.webkit.messageHandlers || Object.keys(window.webkit.messageHandlers).length === 0") as? Bool) == true, "no script message handler is exposed")
    record(!js.webView.configuration.websiteDataStore.isPersistent, "website data store is non-persistent")
    record(js.webView.configuration.userContentController.userScripts.isEmpty, "no injected user scripts")
    record(js.webView.url?.scheme != "file", "document is not a file URL", "url=\(js.webView.url?.absoluteString ?? "nil")")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    await run()
    try? report.joined(separator: "\n").appending("\nfailures=\(failures)\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
    exit(failures == 0 ? 0 : 1)
}
app.run()
