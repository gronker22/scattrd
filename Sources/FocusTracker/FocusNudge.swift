import Foundation

/// Sends a "stop slacking" nudge when today's focus score is low — but only
/// after enough real activity, and rate-limited so it never spams.
final class FocusNudge {
    private let store: Database
    private let notifier: NotificationManager

    private let scoreThreshold = 35
    private let minActiveMinutes = 25.0
    private let cooldown: TimeInterval = 75 * 60     // at most one nudge every 75 minutes

    init(store: Database, notifier: NotificationManager) {
        self.store = store
        self.notifier = notifier
    }

    func check(now: Date = Date()) {
        guard Settings.nudgeEnabled else { return }
        let s = FocusScore.today(store, now: now)
        guard s.hasEnoughData, s.activeMinutes >= minActiveMinutes, s.score < scoreThreshold else { return }
        guard now.timeIntervalSince1970 - Settings.lastNudge >= cooldown else { return }
        Settings.lastNudge = now.timeIntervalSince1970
        notifier.postNudge(score: s.score, switches: s.switches)
    }
}
