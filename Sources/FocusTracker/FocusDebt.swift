import Foundation

/// "Focus Debt" — productive time lost to fragmentation, framed like technical debt.
///
/// Every time real focus is broken by an *immediate* switch (not a deliberate
/// break), you pay a refocus cost: the minutes it takes to rebuild concentration.
/// Summed across the week it becomes a concrete "hours lost" — and, at your
/// hourly rate, a dollar figure. Lost time = lost money.
enum FocusDebt {
    // --- Tunable constants ---
    /// A block at least this long counts as "real focus" worth protecting (8 min).
    static let sustainedFocusSeconds = 480.0
    /// A gap larger than this means you stepped away on purpose (a break, not an interruption).
    static let breakGapSeconds = 120.0
    /// Productive minutes lost rebuilding focus after each interruption (conservative; tunable).
    static let refocusMinutes = 5.0
    static let workdayHours = 8.0

    struct Result {
        var hoursLost: Double
        var interruptions: Int
        var dollarsLost: Double
        var workdayFraction: Double          // hoursLost / 8
    }

    /// Lost hours + interruption count for a single day's merged focus blocks.
    static func forDay(_ blocks: [FocusSession]) -> (hours: Double, interruptions: Int) {
        guard blocks.count > 1 else { return (0, 0) }
        var interruptions = 0
        for i in 0..<(blocks.count - 1) {
            let block = blocks[i], next = blocks[i + 1]
            let wasFocused = block.category == .deepWork || block.duration >= sustainedFocusSeconds
            let gap = next.start - block.end
            if wasFocused && gap < breakGapSeconds {     // pulled away mid-flow
                interruptions += 1
            }
        }
        return (Double(interruptions) * refocusMinutes / 60.0, interruptions)
    }

    /// Running debt across the last 7 days.
    static func forWeek(store: Database, now: Date = Date()) -> Result {
        let cal = Calendar.current
        var hours = 0.0, interruptions = 0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let (s, e) = dayBounds(for: day)
            let stats = FocusScore.analyze(store.sessions(from: s, to: e))
            let d = forDay(stats.blocks)
            hours += d.hours
            interruptions += d.interruptions
        }
        return Result(hoursLost: hours,
                      interruptions: interruptions,
                      dollarsLost: hours * Settings.hourlyRate,
                      workdayFraction: hours / workdayHours)
    }
}
