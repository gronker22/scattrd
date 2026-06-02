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

    private static var scriptCache: [String: NSAppleScript] = [:]
    private static var deniedBundles: Set<String> = []      // stop retrying after a denial

    static func isBrowser(_ bundleId: String?) -> Bool {
        guard let b = bundleId?.lowercased() else { return false }
        return browsers[b] != nil
    }

    /// The active tab's domain for a supported, frontmost browser — or nil to
    /// fall back to app-level tracking (unsupported browser, no web tab, or
    /// permission not granted).
    static func activeTabHost(bundleId: String?) -> String? {
        guard let b = bundleId?.lowercased(),
              let browser = browsers[b],
              !deniedBundles.contains(b) else { return nil }

        let script = compiledScript(for: b, browser: browser)
        var err: NSDictionary?
        let result = script?.executeAndReturnError(&err)

        if let err = err {
            let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            if code == -1743 || code == -1744 {            // user consent required / denied
                deniedBundles.insert(b)
            }
            return nil
        }
        guard let urlString = result?.stringValue, !urlString.isEmpty else { return nil }
        return host(from: urlString)
    }

    /// Call after the user grants permission so we re-attempt previously-denied browsers.
    static func resetPermissionCache() { deniedBundles.removeAll() }

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
