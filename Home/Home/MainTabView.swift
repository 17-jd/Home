import SwiftUI

struct MainTabView: View {
    @State private var scanner = NetworkScanner()

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .environment(scanner)
    }
}
