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

    let subtitle: String
    if let worst = s.topDistractions.first, worst.switchIns >= 12 {
        subtitle = "\(worst.app) broke your focus \(worst.switchIns)× today"
    } else if s.score >= 75 {
        subtitle = "Deep, sustained focus — best stretch \(mins(s.longestFocusMinutes)) min"
    } else if s.score <= 40 {
        subtitle = "Scattered — \(s.switches) context switches today"
    } else if s.longestFocusMinutes >= 30 {
        subtitle = "Your best stretch: \(mins(s.longestFocusMinutes)) min unbroken"
    } else {
        subtitle = "Average focus block was just \(mins(s.avgFocusMinutes)) min"
    }

    let blocks = "\(s.deepWorkBlocks) deep block\(s.deepWorkBlocks == 1 ? "" : "s")"
    let body = "\(s.switches) switches · \(mins(s.avgFocusMinutes)) min avg · \(mins(s.longestFocusMinutes)) min best · \(blocks)"

    return DailyInsight(title: title, subtitle: subtitle, body: body)
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
