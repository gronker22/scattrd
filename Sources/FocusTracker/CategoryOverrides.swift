import Foundation

/// Persistent user-defined category overrides: a name → AppCategory map stored
/// in UserDefaults. "Name" is either an app display name (e.g. "Slack") or a
/// browser-tab host (e.g. "youtube.com") — whatever the session `app` field holds.
///
/// Overrides are applied at read time in Database.sessions(), so they retroactively
/// reclassify historical data without mutating the raw SQLite rows. Disabling the
/// feature reverts all history to default classification instantly.
final class CategoryOverrides {
    static let shared = CategoryOverrides()

    private let d = UserDefaults.standard
    private let enabledKey = "overrides.enabled"
    private let mapKey     = "overrides.map"

    /// Whether the override feature is active. When false, effectiveCategory(_:default:)
    /// always returns the default, so all categorization behaves as if this class didn't exist.
    var enabled: Bool {
        get { d.object(forKey: enabledKey) as? Bool ?? false }
        set { d.set(newValue, forKey: enabledKey) }
    }

    /// Raw override map: app/host name → AppCategory.rawValue.
    /// Stored as a plain [String: Int] dict so it survives app restarts and
    /// doesn't need any custom Codable logic.
    var map: [String: Int] {
        get { d.object(forKey: mapKey) as? [String: Int] ?? [:] }
        set { d.set(newValue, forKey: mapKey) }
    }

    func apply(app: String, category: AppCategory) {
        var m = map; m[app] = category.rawValue; map = m
    }

    func remove(app: String) {
        var m = map; m.removeValue(forKey: app); map = m
    }

    /// Returns the override category if the feature is enabled and an override
    /// exists for `app`; otherwise returns `def`.
    func effectiveCategory(for app: String, default def: AppCategory) -> AppCategory {
        guard enabled, let raw = map[app], let cat = AppCategory(rawValue: raw) else { return def }
        return cat
    }
}
