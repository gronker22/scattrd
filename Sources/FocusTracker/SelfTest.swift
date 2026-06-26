import Foundation

/// Runtime self-test for logic that's hard to verify by eye. Run with
/// `SCATTRD_SELFTEST=1`. Includes a regression check for each of the five
/// metric-consistency bugs — each would have failed before its fix.
enum SelfTest {
    static func run(store: Database) {
        domainChecks()
        metricChecks(store: store)
    }

    // MARK: - Domain categorization

    private static func domainChecks() {
        let samples = [
            "https://www.youtube.com/watch?v=abc", "https://github.com/owner/repo/pull/3",
            "https://mail.google.com/mail/u/0/#inbox", "https://reddit.com/r/swift",
            "https://watchluna.com/movie/inception", "https://freeslots-casino.net/play",
            "https://streamlit.io/docs", "https://www.google.com/search?q=swift",
        ]
        print("DOMAIN EXTRACTION + CATEGORIZATION")
        print(String(repeating: "-", count: 52))
        for url in samples {
            let host = BrowserTabReader.host(from: url)
            let label = host ?? "(non-web → fall back to app)"
            let cat = host.map { AppCatalog.categoryForDomain($0).label } ?? "—"
            print("  " + label.padding(toLength: 34, withPad: " ", startingAt: 0) + "→ " + cat)
        }
    }

    // MARK: - Metric consistency (one check per fixed bug)

    private static func metricChecks(store: Database) {
        print("\nMETRIC CONSISTENCY CHECKS")
        print(String(repeating: "-", count: 52))
        var passed = 0, failed = 0
        func check(_ name: String, _ ok: Bool) {
            print("  [\(ok ? "PASS" : "FAIL")] \(name)")
            ok ? (passed += 1) : (failed += 1)
        }

        let t0 = Date().timeIntervalSince1970
        func sess(_ app: String, _ cat: AppCategory, _ minutes: Double) -> FocusSession {
            FocusSession(app: app, bundleId: nil, category: cat, start: t0, end: t0 + minutes * 60)
        }

        // Bug 1 — deep-work sub-score and deep-work-block count derive from one definition.
        let neutralDay = FocusScore.analyze([sess("randomsite.com", .neutral, 30)])
        check("long neutral block → 0 deep-work blocks AND 0 deep-work score",
              neutralDay.deepWorkBlocks == 0 && neutralDay.deepWorkScore == 0)
        let deepDay = FocusScore.analyze([sess("Xcode", .deepWork, 30)])
        check("30-min deep-work block → ≥1 block AND >0 deep-work score",
              deepDay.deepWorkBlocks >= 1 && deepDay.deepWorkScore > 0)
        check("invariant: never (deep-work score > 0 while blocks == 0)",
              !(neutralDay.deepWorkScore > 0 && neutralDay.deepWorkBlocks == 0))

        // Formula v3 — a long block can no longer mask a fragmented day.
        // One 120-min deep-work block, then ten 1-min work-app blocks (alternating
        // apps so they don't merge; all deep-work, so 0 distraction switches).
        // Old formula: mean block 11.8 min → Sustain capped at 100, longest 120 →
        // Deep work 100, 0 distraction switches → Switching 100 ⇒ score 100 (wrong).
        var frag: [FocusSession] = [sess("Xcode", .deepWork, 120)]
        for i in 0..<10 { frag.append(sess(i % 2 == 0 ? "Terminal" : "iTerm", .deepWork, 1)) }
        let fragDay = FocusScore.analyze(frag)
        check("fragmented day: Sustain uses median (1 min → ~10, not capped at 100)",
              fragDay.sustainScore <= 12)
        check("fragmented day: long morning still scores Deep work highly (>90)",
              fragDay.deepWorkScore > 90)
        check("fragmented day: overall score reflects fragmentation (55–70, not 100) [\(fragDay.score)]",
              fragDay.score >= 55 && fragDay.score <= 70)

        // Switching: deep-work↔deep-work switching is FREE — fragmenting work
        // across tools must NOT lower Switching (only Sustain reflects it).
        let oneLong = FocusScore.analyze([sess("Xcode", .deepWork, 60)])
        let manyWork = FocusScore.analyze((0..<30).map { sess($0 % 2 == 0 ? "Xcode" : "Terminal", .deepWork, 2) })
        check("deep-work↔deep-work switches don't lower Switching (\(Int(manyWork.switchScore)) == \(Int(oneLong.switchScore)))",
              abs(manyWork.switchScore - oneLong.switchScore) < 0.001)
        // …but switching that TOUCHES a distraction still lowers Switching.
        let withDist = FocusScore.analyze((0..<20).flatMap { _ in
            [sess("Xcode", .deepWork, 2), sess("reddit.com", .distraction, 1)]
        })
        check("distraction-involved switching still lowers Switching (\(Int(withDist.switchScore)) < \(Int(oneLong.switchScore)))",
              withDist.switchScore < oneLong.switchScore)

        // Sleep — a long gap between ticks must NOT bridge the open block into one
        // giant session (which would count sleep as focus and draw a huge replay
        // segment). Uses an in-memory DB so it can't pollute real data.
        let mem = Database(path: ":memory:")
        let am = ActivityMonitor(store: mem)
        let base = 1_700_000_000.0
        am.record(app: "Xcode", bundle: nil, category: .deepWork, now: base)
        am.record(app: "Xcode", bundle: nil, category: .deepWork, now: base + 5)
        am.record(app: "Xcode", bundle: nil, category: .deepWork, now: base + 8 * 3600)   // 8h "sleep"
        let recs = mem.sessions(from: base - 10, to: base + 9 * 3600)
        check("sleep gap does not bridge the open block (no >1h session)",
              !recs.contains { $0.duration > 3600 })
        check("sleep gap starts a fresh block instead (2 sessions, not 1)",
              recs.count == 2)
        check("a normal 5s gap still extends the same block",
              recs.first.map { abs($0.duration - 5) < 0.001 } ?? false)

        // Score ↔ Focus Replay correlation: the replay segments ARE the scored
        // blocks, so their total time must equal the scored active minutes and
        // their count must match the scored block count.
        let payload = DashboardData.build(store: store)
        let segMinutes = payload.today.segments.reduce(0.0) { $0 + ($1.end - $1.start) } / 60
        check("replay segments total == scored active minutes",
              abs(segMinutes - payload.today.activeMinutes) < 0.5)
        check("replay segment count == scored block count",
              payload.today.segments.count == FocusScore.today(store).blocks.count)
        check("replay window never extends into the future",
              payload.today.dayEnd <= Date().timeIntervalSince1970 + 1)

        // Bug 2 — every view reports the same total context switches.
        let shared = ContextSwitches.forMonth(store: store).total
        let wrapped = FocusWrapped.compute(store: store, period: .month).totalSwitches
        let villain = VillainAnalysis.detect(store: store).totalSwitches
        check("shared == Wrapped == Villain total (\(shared)/\(wrapped)/\(villain))",
              shared == wrapped && wrapped == villain)
        let cs = ContextSwitches.forMonth(store: store)
        check("per-app context-switch counts sum to total",
              cs.perApp.reduce(0) { $0 + $1.count } == cs.total)

        // Bug 3 — near-tie detection.
        check("equal counts → near-tie", VillainAnalysis.isNearTie(top: 5, runner: 5, total: 100))
        check("0.1pt gap → near-tie", VillainAnalysis.isNearTie(top: 6, runner: 5, total: 1000))
        check("15pt gap → NOT a tie", !VillainAnalysis.isNearTie(top: 20, runner: 5, total: 100))

        // Bug 4 — notification lines never exceed the OS limit (no mid-word/number cut).
        let big = DayStats(score: 82, switches: 5, avgFocusMinutes: 12.3, longestFocusMinutes: 59,
                           deepWorkBlocks: 3, activeMinutes: 240, topDistractions: [], hasEnoughData: true,
                           sustainScore: 90, switchScore: 80, deepWorkScore: 95, blocks: [])
        let insight = makeDailyInsight(big)
        check("notification subtitle ≤ \(notifMaxLine) (\(insight.subtitle.count))", insight.subtitle.count <= notifMaxLine)
        check("notification body ≤ \(notifMaxLine) (\(insight.body.count))", insight.body.count <= notifMaxLine)
        check("clip trims a 43-char line within the limit",
              clip("Deep, sustained focus — best stretch 59 min").count <= notifMaxLine)

        // Bug 5 — the dev-only test button is gated out of release builds.
        check("DEBUG flag is false in this (release) build", !isDebug())

        print("  → \(passed) passed, \(failed) failed")
        if failed > 0 { FileHandle.standardError.write(Data("SELFTEST FAILURES: \(failed)\n".utf8)) }
    }

    private static func isDebug() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
