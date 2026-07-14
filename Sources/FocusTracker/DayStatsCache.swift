import Foundation

/// Memoizes DayStats for completed days. Streaks, Wrapped, Villain and the
/// weekly view all recompute hundreds of past days from raw sessions on every
/// open — but a finished day's stats only change when category overrides do,
/// so they're safe to cache until the next override edit (see CategoryOverrides,
/// which calls `invalidateAll()` on any change).
///
/// Today is never cached — it changes on every tick. Main-thread only, like all
/// Database access.
enum DayStatsCache {
    private static var cache: [String: DayStats] = [:]
    private static let keyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// DayStats for the calendar day containing `day`, cached if that day is
    /// already over (relative to `now`).
    static func stats(store: Database, day: Date, now: Date = Date()) -> DayStats {
        let (s, e) = dayBounds(for: day)
        let (todayStart, _) = dayBounds(for: now)
        guard e <= todayStart else {                        // today (or future): never cache
            return FocusScore.analyze(store.sessions(from: s, to: e))
        }
        let key = keyFmt.string(from: day)
        if let hit = cache[key] { return hit }
        let st = FocusScore.analyze(store.sessions(from: s, to: e))
        cache[key] = st
        return st
    }

    /// Category overrides retroactively reclassify history — drop everything.
    static func invalidateAll() { cache.removeAll() }
}
