import Foundation

/// Detects when a focus streak breaks, fires a notification, and flags the UI so
/// it can play a "streak broke" animation. Throttled so the backward scan doesn't
/// run on every 5-second tick.
final class StreakTracker {
    private let store: Database
    private let notifier: NotificationManager
    private var lastCheck = Date.distantPast

    init(store: Database, notifier: NotificationManager) {
        self.store = store
        self.notifier = notifier
    }

    func check(now: Date = Date()) {
        guard now.timeIntervalSince(lastCheck) >= 600 else { return }   // at most every 10 min
        lastCheck = now

        let current = FocusStreak.current(store: store, threshold: Settings.streakThreshold, now: now)
        let peak = Settings.streakPeak
        if current >= peak {
            Settings.streakPeak = current                  // growing (or steady)
        } else if peak >= 2 {
            // Dropped from its peak → the streak broke.
            Settings.streakJustBroke = true
            Settings.brokenStreakLength = peak
            notifier.postStreakBroken(length: peak)
            Settings.streakPeak = current
        } else {
            Settings.streakPeak = current
        }
    }
}
