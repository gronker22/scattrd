import Foundation

/// Thin UserDefaults wrapper for the daily-summary preferences.
/// Both the scheduler and the menu read/write through here so they stay in sync.
enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let enabled = "dailySummary.enabled"
        static let hour    = "dailySummary.hour"
        static let minute  = "dailySummary.minute"
        static let lastDay = "dailySummary.lastFiredDay"
        static let tabs    = "tracking.browserTabs"
        static let nudge   = "nudge.enabled"
        static let lastNudge = "nudge.last"
        static let streakGoal = "streak.threshold"
        static let streakPeak = "streak.peak"
        static let streakBroke = "streak.justBroke"
        static let streakBrokeLen = "streak.brokenLength"
        static let calendar = "calendar.enabled"
        static let forecast = "forecast.enabled"
        static let forecastDay = "forecast.lastDay"
    }

    static var summaryEnabled: Bool {
        get { d.object(forKey: Key.enabled) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.enabled) }
    }

    /// Hour (0–23) the daily summary fires. Default 17:00.
    static var summaryHour: Int {
        get { d.object(forKey: Key.hour) as? Int ?? 17 }
        set { d.set(newValue, forKey: Key.hour) }
    }

    static var summaryMinute: Int {
        get { d.object(forKey: Key.minute) as? Int ?? 0 }
        set { d.set(newValue, forKey: Key.minute) }
    }

    /// "yyyy-MM-dd" of the last day we fired, so we notify at most once per day.
    static var lastFiredDay: String? {
        get { d.string(forKey: Key.lastDay) }
        set { d.set(newValue, forKey: Key.lastDay) }
    }

    /// Whether to read the active browser tab's domain (needs Automation permission).
    static var tabTrackingEnabled: Bool {
        get { d.object(forKey: Key.tabs) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.tabs) }
    }

    /// "Stop slacking" nudges when focus is low after enough activity.
    static var nudgeEnabled: Bool {
        get { d.object(forKey: Key.nudge) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.nudge) }
    }
    static var lastNudge: Double {
        get { d.double(forKey: Key.lastNudge) }
        set { d.set(newValue, forKey: Key.lastNudge) }
    }

    /// Score a day must reach to extend the focus streak (user-settable).
    static var streakThreshold: Int {
        get { (d.object(forKey: Key.streakGoal) as? Int) ?? 60 }
        set { d.set(min(95, max(30, newValue)), forKey: Key.streakGoal) }
    }
    static var streakPeak: Int {
        get { d.integer(forKey: Key.streakPeak) }
        set { d.set(newValue, forKey: Key.streakPeak) }
    }
    static var streakJustBroke: Bool {
        get { d.bool(forKey: Key.streakBroke) }
        set { d.set(newValue, forKey: Key.streakBroke) }
    }
    static var brokenStreakLength: Int {
        get { d.integer(forKey: Key.streakBrokeLen) }
        set { d.set(newValue, forKey: Key.streakBrokeLen) }
    }

    /// Whether to read calendar meetings (needs Calendar permission).
    static var calendarEnabled: Bool {
        get { d.bool(forKey: Key.calendar) }
        set { d.set(newValue, forKey: Key.calendar) }
    }

    /// Evening next-day focus forecast.
    static var forecastEnabled: Bool {
        get { d.object(forKey: Key.forecast) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.forecast) }
    }
    static var lastForecastDay: String? {
        get { d.string(forKey: Key.forecastDay) }
        set { d.set(newValue, forKey: Key.forecastDay) }
    }

    static var summaryTimeString: String {
        var c = DateComponents(); c.hour = summaryHour; c.minute = summaryMinute
        let date = Calendar.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}
