import Foundation

/// How an app counts toward (or against) focus.
/// Stored as the raw Int in SQLite so categories survive across runs.
enum AppCategory: Int {
    case deepWork = 0       // editors, IDEs, design tools, terminals — where real work happens
    case communication = 1  // Slack, Mail, Zoom — necessary but fragmenting
    case distraction = 2    // Twitter/X, Reddit, YouTube — pure attention drains
    case neutral = 3        // browsers (tab unknown in v1), Finder, unknown apps
    case idle = 4           // user away from keyboard; excluded from all scoring

    var label: String {
        switch self {
        case .deepWork: return "Deep work"
        case .communication: return "Communication"
        case .distraction: return "Distraction"
        case .neutral: return "Neutral"
        case .idle: return "Idle"
        }
    }
}

/// A continuous, uninterrupted stretch of time spent in a single app.
/// A "context switch" is the boundary between two consecutive sessions
/// with different apps.
struct FocusSession {
    let app: String
    let bundleId: String?
    let category: AppCategory
    let start: Double   // unix seconds
    let end: Double      // unix seconds

    var duration: Double { max(0, end - start) }
}

/// Local-day bounds [start, end) as unix timestamps for the given date.
/// Uses the user's current calendar/timezone. DST edge days are close enough for v1.
func dayBounds(for date: Date) -> (start: Double, end: Double) {
    let cal = Calendar.current
    let start = cal.startOfDay(for: date)
    let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    return (start.timeIntervalSince1970, end.timeIntervalSince1970)
}
