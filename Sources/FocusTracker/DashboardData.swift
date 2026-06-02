import Foundation

// Codable DTOs serialized to JSON and embedded in the dashboard HTML.

struct DashboardPayload: Codable {
    let date: String
    let today: TodayPayload
    let week: WeekPayload
}

struct TodayPayload: Codable {
    let hasData: Bool
    let score: Int
    let verdict: String
    let switches: Int
    let avgFocus: Double
    let longestFocus: Double
    let deepWorkBlocks: Int
    let activeMinutes: Double
    let sustain: Int
    let switching: Int
    let deepWork: Int
    let dayStart: Double          // unix sec — timeline left edge
    let dayEnd: Double            // unix sec — timeline right edge
    let segments: [SegmentDTO]
    let hours: [HourDTO]
    let distractions: [DistractionDTO]
}

struct SegmentDTO: Codable {
    let app: String
    let cat: Int
    let start: Double
    let end: Double
}

struct HourDTO: Codable {
    let hour: Int
    let activeMin: Double
    let deepMin: Double
    let switches: Int
}

struct DistractionDTO: Codable {
    let app: String
    let switchIns: Int
    let minutes: Double
}

struct WeekPayload: Codable {
    let days: [DayDTO]
    let morningScore: Int          // deep-work density (%) before noon, across the week
    let afternoonScore: Int        // … after noon
    let bestDay: String
    let worstDay: String
    let debtHours: Double           // Focus Debt: productive hours lost to fragmentation this week
    let debtInterruptions: Int
    let debtDollars: Double
    let debtWorkdayPct: Int         // % of an 8-hour workday
}

struct DayDTO: Codable {
    let label: String              // "Mon"
    let date: String               // "6/1"
    let hasData: Bool
    let score: Int
    let activeMin: Double
    let isToday: Bool
}

/// Builds the full dashboard payload from the database.
enum DashboardData {
    static func build(store: Database, now: Date = Date()) -> DashboardPayload {
        let cal = Calendar.current
        let stats = FocusScore.today(store, now: now)
        let blocks = stats.blocks

        // --- Timeline window: trim to activity (±30 min), else default 8:00–20:00.
        let (dayStartTs, dayEndTs) = dayBounds(for: now)
        let windowStart: Double
        let windowEnd: Double
        if let first = blocks.map({ $0.start }).min(),
           let last = blocks.map({ $0.end }).max() {
            windowStart = max(dayStartTs, first - 1800)
            windowEnd = min(dayEndTs, max(last + 1800, first + 3600))
        } else {
            windowStart = dayStartTs + 8 * 3600
            windowEnd = dayStartTs + 20 * 3600
        }

        let segments = blocks.map {
            SegmentDTO(app: $0.app, cat: $0.category.rawValue, start: $0.start, end: $0.end)
        }

        // --- Hourly attention curve: split each block across the hours it spans.
        var activeByHour = [Double](repeating: 0, count: 24)
        var deepByHour = [Double](repeating: 0, count: 24)
        var switchesByHour = [Int](repeating: 0, count: 24)
        for (i, b) in blocks.enumerated() {
            var t = b.start
            while t < b.end {
                let d = Date(timeIntervalSince1970: t)
                let hour = cal.component(.hour, from: d)
                let hourStartTs = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d))?
                    .timeIntervalSince1970 ?? t
                let chunkEnd = min(b.end, hourStartTs + 3600)
                if chunkEnd <= t { break }                      // safety: never loop forever
                let dur = chunkEnd - t
                if (0..<24).contains(hour) {
                    activeByHour[hour] += dur
                    if b.category == .deepWork { deepByHour[hour] += dur }
                }
                t = chunkEnd
            }
            if i > 0 {
                let h = cal.component(.hour, from: Date(timeIntervalSince1970: b.start))
                if (0..<24).contains(h) { switchesByHour[h] += 1 }
            }
        }
        let hours = (0..<24).map {
            HourDTO(hour: $0, activeMin: activeByHour[$0] / 60,
                    deepMin: deepByHour[$0] / 60, switches: switchesByHour[$0])
        }

        let distractions = stats.topDistractions.map {
            DistractionDTO(app: $0.app, switchIns: $0.switchIns, minutes: $0.totalSeconds / 60)
        }

        let today = TodayPayload(
            hasData: stats.hasEnoughData,
            score: stats.score,
            verdict: verdict(stats.score, hasData: stats.hasEnoughData),
            switches: stats.switches,
            avgFocus: stats.avgFocusMinutes,
            longestFocus: stats.longestFocusMinutes,
            deepWorkBlocks: stats.deepWorkBlocks,
            activeMinutes: stats.activeMinutes,
            sustain: Int(stats.sustainScore.rounded()),
            switching: Int(stats.switchScore.rounded()),
            deepWork: Int(stats.deepWorkScore.rounded()),
            dayStart: windowStart,
            dayEnd: windowEnd,
            segments: segments,
            hours: hours,
            distractions: distractions
        )

        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d"
        return DashboardPayload(date: df.string(from: now), today: today,
                                week: buildWeek(store: store, now: now))
    }

    // --- Last 7 days, plus the morning/afternoon "focus fingerprint".
    private static func buildWeek(store: Database, now: Date) -> WeekPayload {
        let cal = Calendar.current
        let dayLabel = DateFormatter(); dayLabel.dateFormat = "EEE"
        let dateLabel = DateFormatter(); dateLabel.dateFormat = "M/d"

        var days: [DayDTO] = []
        var bestScore = -1, worstScore = 101
        var bestDay = "—", worstDay = "—"
        var morningDeep = 0.0, morningActive = 0.0
        var afternoonDeep = 0.0, afternoonActive = 0.0
        var debtHours = 0.0, debtInterruptions = 0

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let dayDate = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let (s, e) = dayBounds(for: dayDate)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))

            days.append(DayDTO(
                label: dayLabel.string(from: dayDate),
                date: dateLabel.string(from: dayDate),
                hasData: st.hasEnoughData,
                score: st.score,
                activeMin: st.activeMinutes,
                isToday: cal.isDate(dayDate, inSameDayAs: now)
            ))

            if st.hasEnoughData {
                if st.score > bestScore { bestScore = st.score; bestDay = dayLabel.string(from: dayDate) }
                if st.score < worstScore { worstScore = st.score; worstDay = dayLabel.string(from: dayDate) }
            }

            let noon = s + 12 * 3600
            for b in st.blocks {
                let mid = (b.start + b.end) / 2
                if mid < noon {
                    morningActive += b.duration
                    if b.category == .deepWork { morningDeep += b.duration }
                } else {
                    afternoonActive += b.duration
                    if b.category == .deepWork { afternoonDeep += b.duration }
                }
            }

            let d = FocusDebt.forDay(st.blocks)
            debtHours += d.hours
            debtInterruptions += d.interruptions
        }

        let morning = morningActive > 0 ? Int((morningDeep / morningActive * 100).rounded()) : 0
        let afternoon = afternoonActive > 0 ? Int((afternoonDeep / afternoonActive * 100).rounded()) : 0
        return WeekPayload(days: days, morningScore: morning, afternoonScore: afternoon,
                           bestDay: bestDay, worstDay: worstDay,
                           debtHours: debtHours, debtInterruptions: debtInterruptions,
                           debtDollars: debtHours * Settings.hourlyRate,
                           debtWorkdayPct: Int((debtHours / FocusDebt.workdayHours * 100).rounded()))
    }

    private static func verdict(_ score: Int, hasData: Bool) -> String {
        guard hasData else { return "Not enough activity yet today" }
        switch score {
        case 80...:   return "Deep, sustained focus"
        case 60..<80: return "Solid focus with some breaks"
        case 40..<60: return "Fragmented — lots of switching"
        default:      return "Heavily scattered"
        }
    }
}
