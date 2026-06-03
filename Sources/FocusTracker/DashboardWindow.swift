import AppKit
import WebKit

/// Hosts the dashboard in a native WKWebView window, so the Focus Replay opens
/// as part of the app itself rather than in an external browser. One reusable
/// window; each open reloads fresh HTML (so the data is always current).
final class DashboardWindow: NSObject, NSWindowDelegate {
    static let shared = DashboardWindow()

    private var window: NSWindow?
    private var webView: WKWebView?

    // Matches the dashboard's --bg (#0e1014), so there's no white flash on open.
    private let bg = NSColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1)

    func show(html: String) {
        if window == nil { build() }
        webView?.loadHTMLString(html, baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let frame = NSRect(x: 0, y: 0, width: 1320, height: 900)

        let wv = WKWebView(frame: frame)
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
}
