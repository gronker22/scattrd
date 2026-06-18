import Foundation
import AppKit

/// Polls the frontmost app + idle state and records focus sessions to the DB.
/// One open session is kept in memory; each tick either extends it (same app)
/// or closes it and starts a new one (a context switch).
///
/// Sleep handling: the poll timer is suspended while the Mac sleeps, so no ticks
/// fire. Without a guard, the first tick after waking would extend the open block
/// across the whole sleep — counting hours of sleep as focus (and drawing one
/// giant segment in Focus Replay). We close the open block the moment the machine
/// sleeps, and the recording path also refuses to bridge any gap longer than
/// `maxGapSeconds` as a backstop.
final class ActivityMonitor {
    private let store: Database
    private let idleThreshold: Double

    private var currentApp: String?
    private var currentSessionId: Int64?

    /// Timestamp of the last sample we actually recorded. Used to detect a suspend
    /// gap (sleep / display off / stalled timer) and avoid bridging the open block.
    private var lastTickTs: Double = 0
    /// If this many seconds pass with no recorded tick, assume the machine was
    /// asleep/suspended and start a fresh block rather than extending the old one.
    static let maxGapSeconds: Double = 30

    private(set) var isPaused = false

    /// - Parameter idleThreshold: seconds of no input before we count you as "away".
    init(store: Database, idleThreshold: Double = 120) {
        self.store = store
        self.idleThreshold = idleThreshold

        // Close the open block the instant the machine sleeps or the display turns
        // off, so sleep / away time is never counted toward the score.
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.endCurrentSession()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        // Closing the in-memory session means resuming starts a fresh block
        // instead of bridging a long pause gap.
        if paused { endCurrentSession() }
    }

    /// Drops the in-memory open session so the next sample starts a brand-new
    /// block instead of extending across a pause / sleep gap.
    func endCurrentSession() {
        currentApp = nil
        currentSessionId = nil
    }

    /// Called once per poll interval from the main run loop.
    func tick(now: Double = Date().timeIntervalSince1970) {
        guard !isPaused else { return }
        guard let s = sample() else { return }   // skip when scattrd itself is frontmost
        record(app: s.app, bundle: s.bundle, category: s.category, now: now)
    }

    // MARK: - Pieces (split out so the recording logic is unit-testable)

    private struct Sample { let app: String; let bundle: String?; let category: AppCategory }

    /// Reads the current frontmost app / idle state. Returns nil to skip the tick
    /// entirely (scattrd is frontmost — we never track ourselves).
    private func sample() -> Sample? {
        if SystemIdle.seconds() >= idleThreshold {
            return Sample(app: "Idle", bundle: nil, category: .idle)
        }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return Sample(app: "Unknown", bundle: nil, category: .neutral)
        }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        let name = front.localizedName ?? front.bundleIdentifier ?? "Unknown"
        let bundle = front.bundleIdentifier

        // Browser? Resolve the active tab's domain and categorize by site,
        // so tab switches register as real context switches.
        if Settings.tabTrackingEnabled,
           BrowserTabReader.isBrowser(bundle),
           let host = BrowserTabReader.activeTabHost(bundleId: bundle) {
            return Sample(app: host, bundle: bundle, category: AppCatalog.categoryForDomain(host))
        }
        return Sample(app: name, bundle: bundle, category: AppCatalog.category(bundleId: bundle, name: name))
    }

    /// Records a sample at `now`, extending the open block or starting a new one.
    /// Closes the open block first if `now` is more than `maxGapSeconds` past the
    /// last recorded tick (machine slept / timer suspended), so the gap is never
    /// counted as focus time.
    func record(app: String, bundle: String?, category: AppCategory, now: Double) {
        if lastTickTs > 0, now - lastTickTs > Self.maxGapSeconds {
            endCurrentSession()
        }
        lastTickTs = now

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
