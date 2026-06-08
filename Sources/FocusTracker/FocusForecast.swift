import Foundation

struct Forecast {
    let valid: Bool
    let goldenLabel: String       // peak window, e.g. "2–5pm"
    let blockLabel: String        // the 2h deep-work block we'd create, e.g. "2–4pm"
    let blockStart: Date          // tomorrow
    let blockEnd: Date
    let meetingsBeforeNoon: Int
    let totalMeetings: Int
    let conflict: Bool            // a meeting overlaps the peak window tomorrow
    let headline: String          // human message for the notification + card
}

/// Predicts tomorrow: your peak focus window (from history) + upcoming meetings,
/// and proposes a Deep Work block to protect.
enum FocusForecast {
    static func compute(store: Database, now: Date = Date()) -> Forecast {
        let cal = Calendar.current
        let golden = GoldenHours.detect(store: store, now: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now

        let bStart = golden.valid ? golden.startHour : 9
        let blockStart = cal.date(byAdding: .hour, value: bStart, to: tomorrow) ?? tomorrow
        let blockEnd = cal.date(byAdding: .hour, value: 2, to: blockStart) ?? blockStart
        let blockLabel = "\(GoldenHours.hourName(bStart))–\(GoldenHours.hourName(bStart + 2))"

        let tEnd = cal.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        let noon = cal.date(byAdding: .hour, value: 12, to: tomorrow) ?? tomorrow
        var total = 0, beforeNoon = 0, conflict = false
        if CalendarService.shared.isAuthorized {
            let mtgs = CalendarService.shared.meetings(from: tomorrow, to: tEnd)
            total = mtgs.count
            beforeNoon = mtgs.filter { $0.startDate < noon }.count
            if golden.valid,
               let gs = cal.date(byAdding: .hour, value: golden.startHour, to: tomorrow),
               let ge = cal.date(byAdding: .hour, value: golden.endHour, to: tomorrow) {
                conflict = mtgs.contains { $0.startDate < ge && $0.endDate > gs }
            }
        }

        let label = golden.valid ? golden.label : "—"
        let headline: String
        if !golden.valid {
            headline = "Keep tracking — once scattrd learns your rhythm you'll get a next-day focus plan here."
        } else if conflict {
            headline = "⚠️ A meeting overlaps your peak window (\(label)) tomorrow. Move it or block focus elsewhere."
        } else if CalendarService.shared.isAuthorized && total > 0 {
            let m = beforeNoon > 0 ? "\(beforeNoon) meeting\(beforeNoon == 1 ? "" : "s") before noon"
                                   : "\(total) meeting\(total == 1 ? "" : "s")"
            headline = "Tomorrow: \(m). Your best focus window is \(label) — block it now."
        } else {
            headline = "Tomorrow: your best focus window is \(label). Protect it."
        }

        return Forecast(valid: golden.valid, goldenLabel: label, blockLabel: blockLabel,
                        blockStart: blockStart, blockEnd: blockEnd,
                        meetingsBeforeNoon: beforeNoon, totalMeetings: total,
                        conflict: conflict, headline: headline)
    }
}
