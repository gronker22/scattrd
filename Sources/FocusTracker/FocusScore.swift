import Foundation

/// One app's contribution to the distraction leaderboard.
struct AppUsage {
    let app: String
    let category: AppCategory
    var totalSeconds: Double
    var switchIns: Int     // how many times you jumped *into* this app
}

/// Everything the UI needs to describe a day.
struct DayStats {
    var score: Int                  // 0–100, higher = more focused
    var switches: Int
    var avgFocusMinutes: Double
    var longestFocusMinutes: Double
    var deepWorkBlocks: Int
    var activeMinutes: Double
    var topDistractions: [AppUsage]
    var hasEnoughData: Bool

    // Sub-scores kept for transparency / tuning / "why is my score X" UI.
    var sustainScore: Double
    var switchScore: Double
    var deepWorkScore: Double
    /// Merged focus blocks (non-idle, consecutive same-app coalesced) — powers the timeline.
    var blocks: [FocusSession]

    static let empty = DayStats(
        score: 0, switches: 0, avgFocusMinutes: 0, longestFocusMinutes: 0,
        deepWorkBlocks: 0, activeMinutes: 0, topDistractions: [],
        hasEnoughData: false, sustainScore: 0, switchScore: 0, deepWorkScore: 0,
        blocks: []
    )
}

/// The heart of the product: turn a list of raw sessions into a Focus Score.
///
/// Score = 40% sustain + 35% switch + 25% deep-work, each a 0–100 sub-score.
/// The weights and constants below are deliberately easy to tune — this is the
/// differentiator, so it should *feel* right before the UI does.
enum FocusScore {

    // --- Tunable constants -------------------------------------------------
    /// Average block length (minutes) that earns a perfect "sustain" sub-score.
    static let sustainTargetMinutes = 20.0
    /// Switch-rate decay: higher = more forgiving of frequent switching.
    static let switchDecay = 15.0
    /// Longest unbroken block (minutes) that earns a perfect "deep work" sub-score.
    static let deepWorkTargetMinutes = 45.0
    /// A block must be at least this long (and deep-work category) to count as "deep work".
    static let deepWorkMinMinutes = 15.0
    /// Need at least this much active time before a score is meaningful.
    static let minActiveSeconds = 300.0
    // -----------------------------------------------------------------------

    static func analyze(_ raw: [FocusSession]) -> DayStats {
        // 1. Drop idle + sub-second noise.
        let active = raw.filter { $0.category != .idle && $0.duration >= 1 }

        // 2. Merge consecutive same-app sessions into "focus blocks".
        //    Going App A → (idle) → App A reads as one continuous block: you
        //    came back to the same context, so it isn't a real switch.
        var blocks: [FocusSession] = []
        for s in active {
            if let last = blocks.last, last.app == s.app {
                blocks[blocks.count - 1] = FocusSession(
                    app: last.app, bundleId: last.bundleId, category: last.category,
                    start: last.start, end: s.end
                )
            } else {
                blocks.append(s)
            }
        }

        let activeSeconds = blocks.reduce(0) { $0 + $1.duration }
        guard activeSeconds >= minActiveSeconds, !blocks.isEmpty else {
            return DayStats.empty
        }

        // 3. Headline metrics.
        let switches = max(0, blocks.count - 1)
        let activeHours = activeSeconds / 3600
        let switchesPerHour = activeHours > 0 ? Double(switches) / activeHours : 0
        let avgBlockMinutes = (activeSeconds / Double(blocks.count)) / 60
        let longestMinutes = (blocks.map { $0.duration }.max() ?? 0) / 60
        let deepWorkBlocks = blocks.filter {
            $0.category == .deepWork && $0.duration >= deepWorkMinMinutes * 60
        }.count

        // 4. Sub-scores (each clamped to 0–100).
        let sustain = min(100, avgBlockMinutes / sustainTargetMinutes * 100)
        let switchScore = 100 * exp(-switchesPerHour / switchDecay)   // 0/hr→100, 15/hr→37, 30/hr→14
        let deepWork = min(100, longestMinutes / deepWorkTargetMinutes * 100)
        let score = Int((0.40 * sustain + 0.35 * switchScore + 0.25 * deepWork).rounded())

        // 5. Distraction leaderboard: rank the apps that fragment you most,
        //    by how often you switch into them (then by total time).
        var usage: [String: AppUsage] = [:]
        for (i, b) in blocks.enumerated() {
            guard b.category == .distraction || b.category == .communication else { continue }
            var u = usage[b.app] ?? AppUsage(app: b.app, category: b.category, totalSeconds: 0, switchIns: 0)
            u.totalSeconds += b.duration
            if i > 0 { u.switchIns += 1 }
            usage[b.app] = u
        }
        let top = usage.values
            .sorted { ($0.switchIns, $0.totalSeconds) > ($1.switchIns, $1.totalSeconds) }
            .prefix(5)

        return DayStats(
            score: max(0, min(100, score)),
            switches: switches,
            avgFocusMinutes: avgBlockMinutes,
            longestFocusMinutes: longestMinutes,
            deepWorkBlocks: deepWorkBlocks,
            activeMinutes: activeSeconds / 60,
            topDistractions: Array(top),
            hasEnoughData: true,
            sustainScore: sustain,
            switchScore: switchScore,
            deepWorkScore: deepWork,
            blocks: blocks
        )
    }

    /// Convenience: analyze just today's sessions from the store.
    static func today(_ store: Database, now: Date = Date()) -> DayStats {
        let (start, end) = dayBounds(for: now)
        return analyze(store.sessions(from: start, to: end))
    }
}
