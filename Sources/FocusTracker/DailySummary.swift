import Foundation

/// A three-tier notification: an anchor number, a striking hook, and the details.
struct DailyInsight {
    let title: String      // anchor — the score (becomes the daily habit number)
    let subtitle: String   // the hook — one striking, personal stat
    let body: String       // supporting details
}

/// Picks the single most striking angle on the day. This is the "Spotify Wrapped"
/// moment — it should feel personal and a little surprising, not a stat dump.
/// The priority order leads with naming-and-shaming a dominant distraction,
/// then celebrates a great day, then calls out a scattered one.
func makeDailyInsight(_ s: DayStats) -> DailyInsight {
    let emoji: String
    switch s.score {
    case 80...:   emoji = "🧘"
    case 60..<80: emoji = "🙂"
    case 40..<60: emoji = "🌀"
    default:      emoji = "🔥"
    }
    let title = "Today's Focus: \(s.score) \(emoji)"

    func mins(_ m: Double) -> String { m >= 10 ? "\(Int(m.rounded()))" : String(format: "%.1f", m) }

    // Each line is clipped so macOS shows it in full — never cut mid-word/number.
    let subtitle: String
    if let worst = s.topDistractions.first, worst.switchIns >= 12 {
        subtitle = clip("\(worst.app): \(worst.switchIns) interruptions")
    } else if s.score >= 75 {
        subtitle = clip("Deep focus · best run \(mins(s.longestFocusMinutes)) min")
    } else if s.score <= 40 {
        subtitle = clip("Scattered · \(s.switches) switches today")
    } else if s.longestFocusMinutes >= 30 {
        subtitle = clip("Best stretch: \(mins(s.longestFocusMinutes)) min")
    } else {
        subtitle = clip("Avg focus block: \(mins(s.avgFocusMinutes)) min")
    }

    let body = clip("\(s.switches) switches · \(mins(s.avgFocusMinutes))m avg · \(s.deepWorkBlocks) focus")

    return DailyInsight(title: title, subtitle: subtitle, body: body)
}

/// Max characters per notification line that macOS reliably shows in a banner
/// without truncating — kept comfortably under the width so numbers never get cut.
let notifMaxLine = 36

/// Trim to the last whole word within the limit, adding an ellipsis only if cut.
/// Guarantees no mid-word / mid-number truncation regardless of input length.
func clip(_ s: String, max: Int = notifMaxLine) -> String {
    guard s.count > max else { return s }
    var cut = String(s.prefix(max - 1))                 // leave room for the ellipsis
    if let space = cut.lastIndex(of: " ") { cut = String(cut[..<space]) }
    return cut + "…"
}

/// Decides when the daily summary fires and posts it — at most once per day.
/// Cheap to call on every poll tick: the expensive stats query only runs once,
/// at the moment the target time passes.
final class DailySummaryScheduler {
    private let store: Database
    private let notifier: NotificationManager

    init(store: Database, notifier: NotificationManager) {
        self.store = store
        self.notifier = notifier
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func checkAndFireIfDue(now: Date = Date()) {
        guard Settings.summaryEnabled else { return }

        let today = Self.dayKey(now)
        guard Settings.lastFiredDay != today else { return }   // already fired today

        let cal = Calendar.current
        guard let target = cal.date(bySettingHour: Settings.summaryHour,
                                    minute: Settings.summaryMinute, second: 0, of: now),
              now >= target else { return }                    // target time not reached yet

        let stats = FocusScore.today(store, now: now)
        Settings.lastFiredDay = today                          // mark done (even on a quiet day) so we don't nag
        guard stats.hasEnoughData else { return }              // barely used the Mac → stay quiet
        notifier.postDailySummary(stats)
    }
}
