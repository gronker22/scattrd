import Foundation

/// Finds the user's recurring peak-focus window — a 3-hour block — from recent
/// history. Recomputed whenever the dashboard opens, so it sharpens over time.
enum GoldenHours {
    struct Window {
        let valid: Bool
        let startHour: Int      // 0–23
        let endHour: Int        // startHour + 3
        let label: String       // e.g. "9am–12pm"
    }

    static func detect(store: Database, now: Date = Date(), lookbackDays: Int = 21) -> Window {
        let cal = Calendar.current
        var deep = [Double](repeating: 0, count: 24)
        var active = [Double](repeating: 0, count: 24)
        let today = cal.startOfDay(for: now)
        var day = cal.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
        while day <= today {
            let (s, e) = dayBounds(for: day)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))
            for b in st.blocks { distribute(b, active: &active, deep: &deep) }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Prefer deep-work concentration; fall back to overall active time.
        let metric = deep.reduce(0, +) > 0 ? deep : active
        guard metric.reduce(0, +) >= 1800 else {           // need ≥30 min of history
            return Window(valid: false, startHour: 0, endHour: 0, label: "—")
        }
        var bestStart = 9, bestSum = -1.0
        for start in 0...21 {
            let sum = metric[start] + metric[start + 1] + metric[start + 2]
            if sum > bestSum { bestSum = sum; bestStart = start }
        }
        return Window(valid: true, startHour: bestStart, endHour: bestStart + 3,
                      label: "\(hourName(bestStart))–\(hourName(bestStart + 3))")
    }

    private static func distribute(_ b: FocusSession, active: inout [Double], deep: inout [Double]) {
        let cal = Calendar.current
        var t = b.start
        while t < b.end {
            let d = Date(timeIntervalSince1970: t)
            let hour = cal.component(.hour, from: d)
            let hourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d))?
                .timeIntervalSince1970 ?? t
            let chunkEnd = min(b.end, hourStart + 3600)
            if chunkEnd <= t { break }
            let dur = chunkEnd - t
            if (0..<24).contains(hour) {
                active[hour] += dur
                if b.category == .deepWork { deep[hour] += dur }
            }
            t = chunkEnd
        }
    }

    static func hourName(_ h: Int) -> String {
        let hh = ((h % 24) + 24) % 24
        let disp = hh % 12 == 0 ? 12 : hh % 12
        return "\(disp)\(hh < 12 ? "am" : "pm")"
    }
}
