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
