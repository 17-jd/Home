import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct HomeApp: App {

    init() {
        NotificationManager.shared.requestPermission()
        registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Person.self, Device.self])
    }

    // ── Background refresh (fires every ~15 min when app is suspended) ──────
    // Requires in Xcode: Target → Info → add row
    //   Key:   BGTaskSchedulerPermittedIdentifiers
    //   Value: com.stock.home.refresh
    // Also: Signing & Capabilities → + Capability → Background Modes → Background fetch

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.stock.home.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            scheduleNextRefresh()
            refreshTask.setTaskCompleted(success: true)
        }
        scheduleNextRefresh()
    }

    func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: "com.stock.home.refresh")
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
