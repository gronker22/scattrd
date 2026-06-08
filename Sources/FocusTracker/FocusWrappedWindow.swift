import AppKit
import WebKit

/// A window showing the Focus Wrapped card with a This Month / This Year toggle
/// and a Share button. The card is the whole WKWebView, so a snapshot of it is a
/// clean, shareable image. Controls live in a native bottom bar (not in the card).
final class FocusWrappedWindow: NSObject, NSWindowDelegate {
    static let shared = FocusWrappedWindow()

    private var window: NSWindow?
    private var webView: WKWebView!
    private var segmented: NSSegmentedControl!
    private var shareButton: NSButton!
    private var store: Database?
    private var period: WrappedPeriod = .month

    private let cardW: CGFloat = 480, cardH: CGFloat = 720, barH: CGFloat = 58
    private let bg = NSColor(red: 0.039, green: 0.047, blue: 0.071, alpha: 1)

    func show(store: Database) {
        self.store = store
        if window == nil { build() }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH + barH))
        container.wantsLayer = true
        container.layer?.backgroundColor = bg.cgColor

        webView = WKWebView(frame: NSRect(x: 0, y: barH, width: cardW, height: cardH))
        webView.autoresizingMask = [.width, .height]
        if #available(macOS 12.0, *) { webView.underPageBackgroundColor = bg }
        container.addSubview(webView)

        let bar = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: barH))
        bar.autoresizingMask = [.width]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor

        segmented = NSSegmentedControl(labels: ["This Month", "This Year", "Villain 🦹"],
                                       trackingMode: .selectOne, target: self, action: #selector(periodChanged))
        segmented.selectedSegment = 0
        segmented.frame = NSRect(x: 16, y: (barH - 24) / 2, width: 296, height: 24)
        bar.addSubview(segmented)

        shareButton = NSButton(title: "Share", target: self, action: #selector(share))
        shareButton.bezelStyle = .rounded
        shareButton.keyEquivalent = "\r"
        shareButton.frame = NSRect(x: cardW - 104, y: (barH - 30) / 2, width: 88, height: 30)
        shareButton.autoresizingMask = [.minXMargin]
        bar.addSubview(shareButton)

        container.addSubview(bar)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: cardW, height: cardH + barH),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Focus Wrapped"
        win.contentView = container
        win.backgroundColor = bg
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        window = win
    }

    private func reload() {
        guard let store else { return }
        let html: String
        switch segmented.selectedSegment {
        case 2:  html = VillainAnalysis.cardHTML(store: store)
        case 1:  html = FocusWrapped.cardHTML(store: store, period: .year)
        default: html = FocusWrapped.cardHTML(store: store, period: .month)
        }
        webView.loadHTMLString(html, baseURL: nil)
    }

    @objc private func periodChanged() { reload() }

    /// Test helper: switch tabs.
    func selectSegment(_ i: Int) {
        guard window != nil else { return }
        segmented.selectedSegment = i
        reload()
    }

    /// Test helper: render the card and write it to a PNG.
    func snapshotToFile(_ completion: @escaping (String) -> Void) {
        let cfg = WKSnapshotConfiguration()
        cfg.afterScreenUpdates = true
        webView.takeSnapshot(with: cfg) { image, _ in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("scattrd-wrapped-test.png")
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

    @objc private func share() {
        let cfg = WKSnapshotConfiguration()
        cfg.afterScreenUpdates = true
        webView.takeSnapshot(with: cfg) { [weak self] image, _ in
            guard let self, let image else { return }
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
            let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("scattrd-wrapped.png")
            guard let png, (try? png.write(to: url)) != nil else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: self.shareButton.bounds, of: self.shareButton, preferredEdge: .minY)
        }
    }
}
