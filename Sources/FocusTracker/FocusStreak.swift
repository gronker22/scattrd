import Foundation

/// Consecutive days whose focus score cleared the threshold.
///
/// Rules: a no-activity day is skipped (it neither extends nor breaks the streak,
/// so weekends off don't hurt you). A day with data but below the threshold ends
/// the streak. Today, while in progress, never breaks it — today only ever
/// *extends* a streak, once its score clears the bar.
enum FocusStreak {
    static func current(store: Database, threshold: Int, now: Date = Date()) -> Int {
        let cal = Calendar.current
        var streak = 0, noDataRun = 0, first = true
        var day = cal.startOfDay(for: now)
        for _ in 0..<400 {
            let (s, e) = dayBounds(for: day)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))
            if st.hasEnoughData {
                noDataRun = 0
                if st.score >= threshold { streak += 1 }
                else if !first { break }              // a completed day below threshold ends it
            } else {
                noDataRun += 1
                if noDataRun > 10 { break }           // don't span week-long gaps
            }
            first = false
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    static func best(store: Database, threshold: Int, now: Date = Date(), lookbackDays: Int = 365) -> Int {
        let cal = Calendar.current
        var best = 0, run = 0
        let today = cal.startOfDay(for: now)
        var day = cal.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
        while day <= today {
            let (s, e) = dayBounds(for: day)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))
            if st.hasEnoughData {
                if st.score >= threshold { run += 1; best = max(best, run) }
                else { run = 0 }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(best, current(store: store, threshold: threshold, now: now))
    }
}
