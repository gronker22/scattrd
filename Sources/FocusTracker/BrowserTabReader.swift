import Foundation

private enum BrowserKind { case safari, chromium }

/// Reads the active tab's domain from the frontmost browser via AppleScript
/// (the Automation permission — "control Safari/Chrome"). Privacy by design:
/// only the host/domain is ever returned, never the full URL, path, or query.
///
/// Requires `NSAppleEventsUsageDescription` in Info.plist and only works from
/// the packaged `.app`. Firefox isn't scriptable for tab URLs, so it falls back
/// to app-level tracking automatically.
enum BrowserTabReader {

    // bundle id (lowercased) -> (AppleScript app name, kind)
    private static let browsers: [String: (name: String, kind: BrowserKind)] = [
        "com.apple.safari":                 ("Safari", .safari),
        "com.apple.safaritechnologypreview":("Safari Technology Preview", .safari),
        "com.google.chrome":                ("Google Chrome", .chromium),
        "com.google.chrome.canary":         ("Google Chrome Canary", .chromium),
        "com.brave.browser":                ("Brave Browser", .chromium),
        "com.brave.browser.beta":           ("Brave Browser Beta", .chromium),
        "com.microsoft.edgemac":            ("Microsoft Edge", .chromium),
        "com.vivaldi.vivaldi":              ("Vivaldi", .chromium),
        "com.operasoftware.opera":          ("Opera", .chromium),
        "company.thebrowser.browser":       ("Arc", .chromium),
    ]

    /// AppleScript execution can block for seconds if the browser is busy (or a
    /// permission prompt is up), so it never runs on the main thread. All script
    /// objects live on this serial queue; only the results hop back to main.
    private static let scriptQueue = DispatchQueue(label: "scattrd.browser-tab-reader", qos: .utility)
    private static var scriptCache: [String: NSAppleScript] = [:]   // scriptQueue only

    // Main-thread state: last-known host per browser, in-flight refresh flags,
    // and browsers we stop retrying after a permission denial.
    private static var lastHost: [String: String] = [:]
    private static var refreshing: Set<String> = []
    private static var deniedBundles: Set<String> = []

    static func isBrowser(_ bundleId: String?) -> Bool {
        guard let b = bundleId?.lowercased() else { return false }
        return browsers[b] != nil
    }

    /// The active tab's domain for a supported, frontmost browser — or nil to
    /// fall back to app-level tracking (unsupported browser, no web tab, or
    /// permission not granted).
    ///
    /// Non-blocking: returns the last-known host immediately and refreshes it in
    /// the background, so the value can lag by up to one poll interval (~5s) —
    /// a fine trade against freezing the app on a slow browser. Call from main.
    static func activeTabHost(bundleId: String?) -> String? {
        guard let b = bundleId?.lowercased(),
              let browser = browsers[b],
              !deniedBundles.contains(b) else { return nil }

        if !refreshing.contains(b) {
            refreshing.insert(b)
            scriptQueue.async { refreshHost(bundle: b, browser: browser) }
        }
        return lastHost[b]
    }

    /// Runs on scriptQueue. Executes the AppleScript and posts the result back
    /// to the main thread's cache.
    private static func refreshHost(bundle b: String, browser: (name: String, kind: BrowserKind)) {
        let script = compiledScript(for: b, browser: browser)
        var err: NSDictionary?
        let result = script?.executeAndReturnError(&err)

        var newHost: String?
        var denied = false
        if let err = err {
            let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            denied = (code == -1743 || code == -1744)      // user consent required / denied
        } else if let urlString = result?.stringValue, !urlString.isEmpty {
            newHost = host(from: urlString)
        }

        DispatchQueue.main.async {
            refreshing.remove(b)
            if denied { deniedBundles.insert(b) }
            if let newHost { lastHost[b] = newHost } else { lastHost.removeValue(forKey: b) }
        }
    }

    /// Call after the user grants permission so we re-attempt previously-denied browsers.
    static func resetPermissionCache() { deniedBundles.removeAll() }

    /// scriptQueue only.
    private static func compiledScript(for bundle: String, browser: (name: String, kind: BrowserKind)) -> NSAppleScript? {
        if let cached = scriptCache[bundle] { return cached }
        let tab = browser.kind == .safari ? "current tab of front window" : "active tab of front window"
        let source = """
        tell application "\(browser.name)"
        if (count of windows) = 0 then return ""
        return URL of \(tab)
        end tell
        """
        let script = NSAppleScript(source: source)
        scriptCache[bundle] = script
        return script
    }

    /// Extracts a clean domain from a URL. Only http/https; drops path & query.
    static func host(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = comps.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
