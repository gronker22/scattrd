import Foundation

/// Fires the next-day Focus Forecast notification each evening (once per day,
/// after the target hour).
final class ForecastScheduler {
    private let store: Database
    private let notifier: NotificationManager
    private let fireHour = 20            // 8pm

    init(store: Database, notifier: NotificationManager) {
        self.store = store
        self.notifier = notifier
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func check(now: Date = Date()) {
        guard Settings.forecastEnabled else { return }
        let today = Self.dayKey(now)
        guard Settings.lastForecastDay != today else { return }

        let cal = Calendar.current
        guard let target = cal.date(bySettingHour: fireHour, minute: 0, second: 0, of: now),
              now >= target else { return }

        Settings.lastForecastDay = today
        let f = FocusForecast.compute(store: store, now: now)
        guard f.valid else { return }
        notifier.postForecast(f)
    }
}
