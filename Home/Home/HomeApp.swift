import SwiftUI
import SwiftData

@main
struct HomeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Person.self, Device.self])
    }
}
