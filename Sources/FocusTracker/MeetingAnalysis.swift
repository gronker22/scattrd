import Foundation

struct MeetingDTO: Codable {
    let title: String
    let startTs: Double
    let endTs: Double
    let postScore: Int   // focus score of the hour after the meeting; -1 if not measurable
    let drop: Int        // dayScore − postScore, clamped ≥0 (0 if n/a)
}

struct MeetingRankDTO: Codable {
    let title: String
    let avgDrop: Int
    let count: Int
}

/// Correlates calendar meetings with the focus that followed them.
enum MeetingAnalysis {
    /// Focus score of the hour after a meeting; -1 if the meeting hasn't ended
    /// or there isn't enough activity to score.
    static func postScore(store: Database, end: Date, now: Date) -> Int {
        guard end <= now else { return -1 }
        let s = end.timeIntervalSince1970
        let st = FocusScore.analyze(store.sessions(from: s, to: s + 3600))
        return st.hasEnoughData ? st.score : -1
    }

    static func today(store: Database, now: Date = Date()) -> [MeetingDTO] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        let dayScore = FocusScore.today(store, now: now).score
        return CalendarService.shared.meetings(from: start, to: end).map { ev in
            let ps = postScore(store: store, end: ev.endDate, now: now)
            return MeetingDTO(title: ev.title ?? "(untitled)",
                              startTs: ev.startDate.timeIntervalSince1970,
                              endTs: ev.endDate.timeIntervalSince1970,
                              postScore: ps,
                              drop: ps >= 0 ? max(0, dayScore - ps) : 0)
        }
    }

    /// Meeting titles that most consistently tank focus, over the last 7 days.
    static func weeklyWorst(store: Database, now: Date = Date()) -> [MeetingRankDTO] {
        let cal = Calendar.current
        var agg: [String: (total: Int, count: Int)] = [:]
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let (s, e) = dayBounds(for: day)
            let dayScore = FocusScore.analyze(store.sessions(from: s, to: e)).score
            let evs = CalendarService.shared.meetings(from: Date(timeIntervalSince1970: s),
                                                      to: Date(timeIntervalSince1970: e))
            for ev in evs {
                let ps = postScore(store: store, end: ev.endDate, now: now)
                guard ps >= 0 else { continue }
                let key = (ev.title ?? "(untitled)").trimmingCharacters(in: .whitespaces)
                var cur = agg[key] ?? (0, 0)
                cur.total += max(0, dayScore - ps); cur.count += 1
                agg[key] = cur
            }
        }
        let ranked = agg.map { MeetingRankDTO(title: $0.key,
                                              avgDrop: $0.value.count > 0 ? $0.value.total / $0.value.count : 0,
                                              count: $0.value.count) }
            .filter { $0.avgDrop > 0 }
            .sorted { $0.avgDrop > $1.avgDrop }
        return Array(ranked.prefix(5))
    }
}
