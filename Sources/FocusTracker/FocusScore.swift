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
    /// Median block length (minutes) that earns a perfect "sustain" sub-score.
    /// (v3: Sustain uses the median, not the mean — one long block can no longer
    /// mask a fragmented day.)
    static let sustainTargetMinutes = 10.0
    /// Decay for distraction-only switching: higher = more forgiving.
    static let switchDecay = 30.0
    /// Decay for all-transition (work-to-work included) switching. Higher than
    /// switchDecay so normal dev-tool hopping isn't punished — it only drags the
    /// score down when fragmentation is extreme.
    static let totalSwitchDecay = 60.0
    /// Blend weights inside the Switching sub-score: distraction-only vs. overall
    /// fragmentation. Must sum to 1.
    static let distractionSwitchWeight = 0.7
    static let totalSwitchWeight = 0.3
    /// Longest unbroken block (minutes) that earns a perfect "deep work" sub-score.
    static let deepWorkTargetMinutes = 25.0
    /// Total qualifying deep-work minutes that earns a perfect "total" component —
    /// rewards several solid sessions, not just one long stretch.
    static let deepWorkTotalTargetMinutes = 45.0
    /// Blend weights inside the Deep work sub-score: longest block vs. total
    /// qualifying minutes. Must sum to 1.
    static let deepWorkLongestWeight = 0.6
    static let deepWorkTotalWeight = 0.4
    /// A block must be at least this long (and deep-work category) to count as "deep work".
    static let deepWorkMinMinutes = 12.0
    /// Need at least this much active time before a score is meaningful (~3 min,
    /// so a short focused session still gets scored).
    static let minActiveSeconds = 180.0
    // -----------------------------------------------------------------------

    /// THE single definition of a "deep-work block": a deep-work-category block
    /// at least `deepWorkMinMinutes` long. Both the counter and the deep-work
    /// sub-score derive from this, so they can never disagree.
    static func deepWorkBlocks(in blocks: [FocusSession]) -> [FocusSession] {
        blocks.filter { $0.category == .deepWork && $0.duration >= deepWorkMinMinutes * 60 }
    }

    /// THE single definition of a counted context switch: you landed in a
    /// non-work context (neutral or distraction). Used everywhere switches are counted.
    static func isContextSwitch(_ category: AppCategory) -> Bool {
        category != .deepWork && category != .communication
    }

    /// Median of the given blocks' lengths, in minutes (average of the two middle
    /// values when the count is even). 0 for an empty list. Robust to a single
    /// long block dragging a mean upward.
    static func medianMinutes(_ blocks: [FocusSession]) -> Double {
        let mins = blocks.map { $0.duration / 60 }.sorted()
        guard !mins.isEmpty else { return 0 }
        let n = mins.count
        return n % 2 == 1 ? mins[n / 2] : (mins[n / 2 - 1] + mins[n / 2]) / 2
    }

    /// Bumped when the formula changes in a way that shifts historical day scores.
    /// v2: deep-work sub-score derives from actual deep-work blocks (was
    /// longest-block-of-any-category).
    /// v3: Sustain uses median block length (was mean); Switching blends
    /// distraction-only with fragmentation; Deep work blends the longest
    /// qualifying block with total qualifying minutes.
    /// v4: the fragmentation term only counts transitions that touch a non-work
    /// (neutral/distraction) context — switching between two work tools is free.
    /// Scores aren't stored, so every view recomputes from raw sessions.
    static let scoringVersion = 4

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
        // `switches` is the distraction-only count (landing in a NON-work
        // context — see isContextSwitch). This is the "context switches" figure
        // every other view reports, so its meaning is deliberately unchanged.
        var switches = 0
        for i in 1..<max(1, blocks.count) where isContextSwitch(blocks[i].category) { switches += 1 }

        let activeHours = activeSeconds / 3600
        let distractionSwitchesPerHour = activeHours > 0 ? Double(switches) / activeHours : 0
        // Fragmentation transitions: a block-to-block change only counts if it
        // TOUCHES a non-work (neutral/distraction) context on either side.
        // Switching between two work tools (deep-work or communication) — e.g.
        // Xcode → Terminal → Figma — is normal work and is completely free.
        var fragTransitions = 0
        for i in 1..<max(1, blocks.count)
        where isContextSwitch(blocks[i].category) || isContextSwitch(blocks[i - 1].category) {
            fragTransitions += 1
        }
        let fragSwitchesPerHour = activeHours > 0 ? Double(fragTransitions) / activeHours : 0

        let avgBlockMinutes = (activeSeconds / Double(blocks.count)) / 60   // displayed "avg block"
        let medianBlockMinutes = medianMinutes(blocks)                      // drives Sustain
        let longestMinutes = (blocks.map { $0.duration }.max() ?? 0) / 60

        // Deep-work blocks come from ONE definition, used for the counter AND
        // both deep-work sub-score components — so they can't drift apart.
        let dw = deepWorkBlocks(in: blocks)
        let longestDeepWorkMinutes = (dw.map { $0.duration }.max() ?? 0) / 60
        let totalDeepWorkMinutes = dw.reduce(0) { $0 + $1.duration } / 60

        // 4. Sub-scores (each clamped to 0–100).
        // Sustain: median block length, so one long block can't mask fragmentation.
        let sustain = min(100, medianBlockMinutes / sustainTargetMinutes * 100)

        // Switching: blend distraction-only switching (landing in a non-work app)
        // with distraction-involved fragmentation (any transition touching a
        // non-work context). Pure work↔work switching never lowers the score.
        let distractionSwitching = 100 * exp(-distractionSwitchesPerHour / switchDecay)
        let totalSwitching = 100 * exp(-fragSwitchesPerHour / totalSwitchDecay)
        let switchScore = distractionSwitchWeight * distractionSwitching
                        + totalSwitchWeight * totalSwitching

        // Deep work: blend the longest qualifying block with total qualifying time.
        let longestComponent = min(100, longestDeepWorkMinutes / deepWorkTargetMinutes * 100)
        let totalComponent = min(100, totalDeepWorkMinutes / deepWorkTotalTargetMinutes * 100)
        let deepWork = deepWorkLongestWeight * longestComponent
                     + deepWorkTotalWeight * totalComponent

        let score = Int((0.40 * sustain + 0.35 * switchScore + 0.25 * deepWork).rounded())

        // 5. Distraction leaderboard: rank only true distractions (Twitter, YouTube,
        //    Reddit, etc.) by how often you switch into them (then by total time).
        //    Communication apps (Slack, Mail, …) are necessary work, not distractions,
        //    so they're deliberately excluded here.
        var usage: [String: AppUsage] = [:]
        for (i, b) in blocks.enumerated() {
            guard b.category == .distraction else { continue }
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
            deepWorkBlocks: dw.count,
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
