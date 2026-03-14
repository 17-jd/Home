import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(NetworkScanner.self) private var scanner
    @Environment(\.modelContext)      private var context
    @Query var people:  [Person]
    @Query var devices: [Device]

    @AppStorage("subnetBase")             private var subnetBase             = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("notifyArrivals")         private var notifyArrivals         = true
    @AppStorage("notifyDepartures")       private var notifyDepartures       = true

    @State private var showAddPerson   = false
    @State private var showConfirmWipe = false

    private var assignedIPs: Set<String> { Set(devices.map { $0.lastKnownIP }) }
    private var newDeviceCount: Int { scanner.results.filter { !assignedIPs.contains($0.ip) }.count }

    var body: some View {
        NavigationStack {
            Form {
                // ── Notifications ──────────────────────────────────────────────
                Section {
                    Toggle(isOn: $notifyArrivals) {
                        Label("Arrival alerts", systemImage: "arrow.down.circle.fill")
                    }.tint(.green)
                    Toggle(isOn: $notifyDepartures) {
                        Label("Departure alerts", systemImage: "arrow.up.circle.fill")
                    }.tint(.orange)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Departure alerts fire after 2 consecutive failed checks (~3 min) to avoid false alarms for sleeping devices.")
                }

                // ── Discovered devices ─────────────────────────────────────────
                Section {
                    if scanner.results.isEmpty {
                        Label("Run a scan to discover devices", systemImage: "wifi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(scanner.results) { result in
                            DiscoveredDeviceRow(result: result,
                                               isNew: !assignedIPs.contains(result.ip))
                        }
                    }
                } header: {
                    HStack {
                        Text("Discovered Devices")
                        Spacer()
                        if newDeviceCount > 0 {
                            Text("\(newDeviceCount) new")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                        }
                    }
                } footer: {
                    if !scanner.results.isEmpty {
                        Text("\(scanner.results.count) device\(scanner.results.count == 1 ? "" : "s") online · tap Scan Network to refresh")
                    }
                }

                // ── Network ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Subnet")
                        Spacer()
                        TextField("e.g. 192.168.1", text: $subnetBase)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    Button("Auto-detect") { subnetBase = NetworkScanner.detectSubnet() }
                } header: {
                    Text("Network")
                } footer: {
                    Text("First three octets of your local IP — e.g. 192.168.1")
                }

                // ── Household ──────────────────────────────────────────────────
                Section {
                    ForEach(people) { person in
                        NavigationLink(destination: PersonDetailView(person: person)) {
                            HStack(spacing: 12) {
                                Text(person.emoji).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name).font(.headline)
                                    Text("\(person.devices.count) device\(person.devices.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in offsets.forEach { context.delete(people[$0]) } }

                    Button { showAddPerson = true } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Household Members (\(people.count))")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button("Re-run Setup", role: .destructive) { showConfirmWipe = true }
                } footer: {
                    Text("Wipes all people and devices, then restarts the setup scan.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { EditButton() }
            .sheet(isPresented: $showAddPerson) { AddPersonView() }
            .confirmationDialog(
                "This will delete all people and devices and restart setup.",
                isPresented: $showConfirmWipe,
                titleVisibility: .visible
            ) {
                Button("Wipe & Re-run Setup", role: .destructive) { wipeAndRestart() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func wipeAndRestart() {
        devices.forEach { context.delete($0) }
        people.forEach  { context.delete($0) }
        try? context.save()
        hasCompletedOnboarding = false
    }
}

// MARK: - Discovered device row

private struct DiscoveredDeviceRow: View {
    let result: ScanResult
    let isNew:  Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.hostname ?? result.ip)
                    .font(.headline)
                    .lineLimit(1)
                if result.hostname != nil {
                    Text(result.ip)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isNew {
                Text("NEW")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue, in: Capsule())
            }

            if let ms = result.pingMs {
                Text("\(ms)ms")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(pingColor(ms))
                    .frame(minWidth: 38, alignment: .trailing)
            }
        }
    }

    private func pingColor(_ ms: Int) -> Color {
        switch ms {
        case ..<10:  return .green
        case ..<50:  return .yellow
        default:     return .orange
        }
    }
}
