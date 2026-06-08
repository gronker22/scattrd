import Foundation
import EventKit

/// Reads meetings from macOS Calendar via EventKit — which surfaces every account
/// configured there (iCloud, Google, Exchange…). Permission-gated; only works
/// from the packaged .app (needs the usage-description Info.plist keys).
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    func requestAccess(_ completion: ((Bool) -> Void)? = nil) {
        guard Bundle.main.bundleIdentifier != nil else { completion?(false); return }
        let done: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    /// Timed (non-all-day) meetings in [start, end), excluding ones you declined.
    func meetings(from start: Date, to end: Date) -> [EKEvent] {
        guard isAuthorized, end > start else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > $0.startDate && !declined($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Creates a "Deep Work" event in the default calendar. Needs write (full) access.
    @discardableResult
    func createDeepWorkBlock(start: Date, end: Date) -> Bool {
        guard isAuthorized, let calendar = store.defaultCalendarForNewEvents else { return false }
        let ev = EKEvent(eventStore: store)
        ev.title = "Deep Work"
        ev.notes = "Blocked by scattrd — your peak focus window."
        ev.startDate = start
        ev.endDate = end
        ev.calendar = calendar
        do { try store.save(ev, span: .thisEvent); return true } catch { return false }
    }

    private func declined(_ ev: EKEvent) -> Bool {
        guard let me = ev.attendees?.first(where: { $0.isCurrentUser }) else { return false }
        return me.participantStatus == .declined
    }
}
