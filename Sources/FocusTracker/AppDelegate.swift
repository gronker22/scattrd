import AppKit

/// Wires the pieces together and drives the poll loop.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How often we sample the active app. 5s balances accuracy vs. overhead.
    private let pollInterval: TimeInterval = 5

    private var store: Database!
    private var monitor: ActivityMonitor!
    private var menu: MenuBarController!
    private var notifier: NotificationManager!
    private var summaryScheduler: DailySummaryScheduler!
    private var nudge: FocusNudge!
    private var streakTracker: StreakTracker!
    private var forecastScheduler: ForecastScheduler!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Database(path: Database.standardLocation())
        DashboardWindow.shared.configure(store: store)

        if ProcessInfo.processInfo.environment["SCATTRD_SELFTEST"] != nil {
            SelfTest.run(store: store); exit(0)
        }

        // Test hook: dump the dashboard HTML and exit, without showing any UI.
        if ProcessInfo.processInfo.environment["SCATTRD_DUMP_DASHBOARD"] != nil {
            let url = Dashboard.generate(store: store)
            FileHandle.standardOutput.write(Data((url.path + "\n").utf8))
            exit(0)
        }

        if ProcessInfo.processInfo.environment["SCATTRD_SNAP_WRAPPED"] != nil {
            FocusWrappedWindow.shared.show(store: store)
            if let seg = ProcessInfo.processInfo.environment["SCATTRD_SNAP_SEGMENT"], let i = Int(seg) {
                FocusWrappedWindow.shared.selectSegment(i)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                FocusWrappedWindow.shared.snapshotToFile { p in
                    FileHandle.standardOutput.write(Data((p + "\n").utf8)); exit(0)
                }
            }
            return
        }

        monitor = ActivityMonitor(store: store)
        menu = MenuBarController(store: store)
        menu.onPauseToggle = { [weak self] paused in
            self?.monitor.setPaused(paused)
        }

        notifier = NotificationManager()
        notifier.onOpenSummary = { [weak self] in self?.menu.presentSummary() }
        notifier.setUp()
        summaryScheduler = DailySummaryScheduler(store: store, notifier: notifier)
        nudge = FocusNudge(store: store, notifier: notifier)
        streakTracker = StreakTracker(store: store, notifier: notifier)
        if Settings.calendarEnabled { CalendarService.shared.requestAccess() }
        forecastScheduler = ForecastScheduler(store: store, notifier: notifier)

        menu.onSendTestSummary = { [weak self] in
            guard let self else { return }
            self.notifier.postTest(FocusScore.today(self.store))
        }
        menu.onOpenDashboard = { [weak self] in
            guard let self else { return }
            DashboardWindow.shared.show(html: Dashboard.htmlString(store: self.store))
        }
        menu.onOpenWrapped = { [weak self] in
            guard let self else { return }
            FocusWrappedWindow.shared.show(store: self.store)
        }

        // First sample immediately so the bar isn't blank, then poll on a timer.
        tick()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps the timer firing while menus are open / during tracking.
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Instant switch detection: react the moment the frontmost app changes,
        // instead of waiting up to 5s for the next poll.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Demo/onboarding: open the dashboard window straight away if asked.
        if CommandLine.arguments.contains("--show-dashboard") {
            DashboardWindow.shared.show(html: Dashboard.htmlString(store: store))
        }

        if ProcessInfo.processInfo.environment["SCATTRD_SNAP_PANEL"] != nil {
            menu.snapshotPanel { p in FileHandle.standardOutput.write(Data((p + "\n").utf8)); exit(0) }
        }

        if ProcessInfo.processInfo.environment["SCATTRD_SNAP_DASHBOARD"] != nil {
            DashboardWindow.shared.show(html: Dashboard.htmlString(store: store))
            let js = ProcessInfo.processInfo.environment["SCATTRD_SNAP_JS"]
            DashboardWindow.shared.snapshotToFile(runJS: js) { p in
                FileHandle.standardOutput.write(Data((p + "\n").utf8)); exit(0)
            }
        }
    }

    private func tick() {
        monitor.tick()
        menu.refreshTitle()
        summaryScheduler.checkAndFireIfDue()
        nudge.check()
        streakTracker.check()
        forecastScheduler.check()
    }

    @objc private func activeAppChanged(_ note: Notification) {
        tick()   // instant — record the switch and refresh the bar without waiting for the timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }
}
