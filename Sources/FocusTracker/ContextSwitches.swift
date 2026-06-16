import Foundation

struct ContextSwitchStats {
    let total: Int
    /// Per destination app: how many context switches landed in it.
    /// Invariant: the counts sum to `total`.
    let perApp: [(app: String, count: Int, category: AppCategory)]
}

/// The single source of truth for "context switches" over a period. The daily
/// dashboard and weekly view read `DayStats.switches`; Wrapped and Villain call
/// `forRange`/`forMonth` here. All of them use the SAME predicate
/// (`FocusScore.isContextSwitch`), so the totals can never disagree.
enum ContextSwitches {
    static func forRange(store: Database, from start: Date, to end: Date) -> ContextSwitchStats {
        let cal = Calendar.current
        var total = 0
        var counts: [String: Int] = [:]
        var cats: [String: AppCategory] = [:]
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while day <= last {
            let (s, e) = dayBounds(for: day)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))
            total += st.switches                      // same number the daily score uses
            let blocks = st.blocks
            if blocks.count > 1 {
                for i in 1..<blocks.count where FocusScore.isContextSwitch(blocks[i].category) {
                    counts[blocks[i].app, default: 0] += 1
                    cats[blocks[i].app] = blocks[i].category
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let perApp = counts
            .map { (app: $0.key, count: $0.value, category: cats[$0.key] ?? .neutral) }
            .sorted { $0.count > $1.count }
        return ContextSwitchStats(total: total, perApp: perApp)
    }

    static func forMonth(store: Database, now: Date = Date()) -> ContextSwitchStats {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return forRange(store: store, from: start, to: now)
    }
}
