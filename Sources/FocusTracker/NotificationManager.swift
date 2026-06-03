import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter for local daily-summary notifications.
///
/// Important: UNUserNotificationCenter throws an uncatchable exception if touched
/// from a process with no bundle identifier (i.e. the raw `.build/scattrd`
/// binary). So everything here is gated on `Bundle.main.bundleIdentifier`, and
/// notifications only work when launched from the packaged `scattrd.app`.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var available = false
    private(set) var authorized = false

    /// Called when the user taps a delivered notification.
    var onOpenSummary: (() -> Void)?

    /// Request authorization on launch. No-ops (safely) for the unbundled binary.
    func setUp() {
        guard Bundle.main.bundleIdentifier != nil else {
            FileHandle.standardError.write(Data("scattrd: no bundle id — notifications disabled (run scattrd.app)\n".utf8))
            return
        }
        available = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorized = granted }
        }
    }

    func postDailySummary(_ stats: DayStats) {
        post(makeDailyInsight(stats), id: "daily-summary")
    }

    /// Fired by the "Send Test Summary Now" menu item so the user can see it live.
    func postTest(_ stats: DayStats) {
        let insight = stats.hasEnoughData
            ? makeDailyInsight(stats)
            : DailyInsight(title: "scattrd",
                           subtitle: "Notifications are working ✅",
                           body: "Your real summary arrives at \(Settings.summaryTimeString) once you've logged some activity.")
        post(insight, id: "daily-summary-test")
    }

    /// "Stop slacking" nudge when today's score is low.
    func postNudge(score: Int, switches: Int) {
        let options = [
            ("Stop slacking 👀", "Focus is \(score)/100 — \(switches) switches today. Time to lock in."),
            ("You're scattered", "\(score)/100 right now. Pick one thing and stay with it for 20 minutes."),
            ("Refocus 🎯", "\(score)/100 — you're bouncing between apps. Close the distractions and dig in."),
        ]
        let pick = options.randomElement()!
        post(DailyInsight(title: pick.0, subtitle: pick.1, body: ""), id: "nudge")
    }

    private func post(_ insight: DailyInsight, id: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = insight.title
        content.subtitle = insight.subtitle
        content.body = insight.body
        content.sound = .default
        // nil trigger = deliver immediately, with content computed right now.
        let request = UNNotificationRequest(identifier: "\(id)-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show the banner even when the app is "active" (it's a menubar accessory).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // Tapping the notification opens the full summary.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onOpenSummary?() }
        completionHandler()
    }
}
