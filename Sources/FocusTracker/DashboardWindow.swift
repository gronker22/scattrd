import AppKit
import WebKit

/// Hosts the dashboard in a native WKWebView window, so the Focus Replay opens
/// as part of the app itself rather than in an external browser. One reusable
/// window; each open reloads fresh HTML (so the data is always current).
///
/// The "customize" script-message handler lets the Customize bar JS post override
/// changes back to Swift, which persists them and immediately syncs the new state
/// back to the page via evaluateJavaScript — no full reload needed.
final class DashboardWindow: NSObject, NSWindowDelegate {
    static let shared = DashboardWindow()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var store: Database?

    // Matches the dashboard's --bg (#0e1014), so there's no white flash on open.
    private let bg = NSColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1)

    /// Must be called once (from AppDelegate) before the first show(), so the
    /// script-message handler can access the database for override operations.
    func configure(store: Database) {
        self.store = store
    }

    func show(html: String) {
        if window == nil { build() }
        webView?.loadHTMLString(html, baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Test helper: render the dashboard (optionally running JS first) to a PNG.
    func snapshotToFile(runJS: String?, _ completion: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let wv = self.webView else { completion(""); return }
            let take = {
                let cfg = WKSnapshotConfiguration(); cfg.afterScreenUpdates = true
                wv.takeSnapshot(with: cfg) { image, _ in
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("scattrd-dash-test.png")
                    if let image {
                        var rect = CGRect(origin: .zero, size: image.size)
                        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                            try? png.write(to: url)
                        }
                    }
                    completion(url.path)
                }
            }
            if let js = runJS {
                wv.evaluateJavaScript(js) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: take)
                }
            } else { take() }
        }
    }

    private func build() {
        let frame = NSRect(x: 0, y: 0, width: 1320, height: 900)

        let ucc = WKUserContentController()
        ucc.add(self, name: "customize")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        let wv = WKWebView(frame: frame, configuration: cfg)
        if #available(macOS 12.0, *) { wv.underPageBackgroundColor = bg }

        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "scattrd — Daily Replay"
        win.contentView = wv
        win.minSize = NSSize(width: 940, height: 640)
        win.backgroundColor = bg
        win.isReleasedWhenClosed = false      // keep it around so we can reopen
        win.center()
        win.delegate = self

        window = win
        webView = wv
    }

    // MARK: - JS → Swift customize bridge

    /// Sends the current override state back to the page without a full reload,
    /// so the search input and picker stay visible.
    private func syncToJS() {
        let state: [String: Any] = [
            "enabled": CategoryOverrides.shared.enabled,
            "overrides": CategoryOverrides.shared.map
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window._syncCustomize(\(json))", completionHandler: nil)
    }
}

// MARK: - WKScriptMessageHandler

extension DashboardWindow: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else { return }

        let ov = CategoryOverrides.shared
        switch action {
        case "customize:toggle":
            ov.enabled.toggle()

        case "customize:set":
            guard let app = obj["app"] as? String,
                  let catRaw = obj["cat"] as? Int,
                  let cat = AppCategory(rawValue: catRaw) else { return }
            ov.apply(app: app, category: cat)

        case "customize:remove":
            guard let app = obj["app"] as? String else { return }
            ov.remove(app: app)

        default:
            break
        }

        syncToJS()
    }
}
