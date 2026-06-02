import Foundation
import AppKit

/// Polls the frontmost app + idle state and records focus sessions to the DB.
/// One open session is kept in memory; each tick either extends it (same app)
/// or closes it and starts a new one (a context switch).
final class ActivityMonitor {
    private let store: Database
    private let idleThreshold: Double

    private var currentApp: String?
    private var currentSessionId: Int64?

    private(set) var isPaused = false

    /// - Parameter idleThreshold: seconds of no input before we count you as "away".
    init(store: Database, idleThreshold: Double = 120) {
        self.store = store
        self.idleThreshold = idleThreshold
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        // Closing the in-memory session means resuming starts a fresh block
        // instead of bridging a long pause gap.
        if paused {
            currentApp = nil
            currentSessionId = nil
        }
    }

    /// Called once per poll interval from the main run loop.
    func tick() {
        guard !isPaused else { return }
        let now = Date().timeIntervalSince1970

        var app = "Unknown"
        var bundle: String? = nil
        var category: AppCategory = .neutral

        if SystemIdle.seconds() >= idleThreshold {
            app = "Idle"; category = .idle
        } else if let front = NSWorkspace.shared.frontmostApplication {
            if front.bundleIdentifier == Bundle.main.bundleIdentifier { return }   // never track scattrd itself
            let name = front.localizedName ?? front.bundleIdentifier ?? "Unknown"
            bundle = front.bundleIdentifier

            // Browser? Resolve the active tab's domain and categorize by site,
            // so tab switches register as real context switches.
            if Settings.tabTrackingEnabled,
               BrowserTabReader.isBrowser(bundle),
               let host = BrowserTabReader.activeTabHost(bundleId: bundle) {
                app = host
                category = AppCatalog.categoryForDomain(host)
            } else {
                app = name
                category = AppCatalog.category(bundleId: bundle, name: name)
            }
        }

        if app == currentApp, let id = currentSessionId {
            store.updateSessionEnd(id: id, end: now)        // extend current block
        } else {
            currentApp = app                                 // a context switch
            currentSessionId = store.startSession(
                app: app, bundleId: bundle, category: category.rawValue, start: now
            )
        }
    }
}
