import SwiftUI
import SwiftData

struct DeviceSetupView: View {
    let results: [ScanResult]

    @Environment(\.modelContext) private var context
    @Query var people: [Person]
    @Query var existingDevices: [Device]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var rows: [DeviceRow] = []
    @State private var showAddPerson = false

    // Filter out IPs already registered — no need to rename them
    private var newResults: [ScanResult] {
        results.filter { result in
            !existingDevices.contains { $0.lastKnownIP == result.ip }
        }
    }

    // Already registered devices found in this scan
    private var knownResults: [ScanResult] {
        results.filter { result in
            existingDevices.contains { $0.lastKnownIP == result.ip }
        }
    }

    init(results: [ScanResult]) {
        self.results = results
    }

    var body: some View {
        List {
            if results.isEmpty {
                Section {
                    Label("No devices were found. You can add devices later from Settings → Re-run Setup.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Already-known devices — show as read-only
            if !knownResults.isEmpty {
                Section("Already Registered") {
                    ForEach(knownResults) { result in
                        let device = existingDevices.first { $0.lastKnownIP == result.ip }
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device?.label ?? result.ip).font(.headline)
                                Text(result.ip)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let person = device?.person {
                                Text("\(person.emoji) \(person.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // New devices — let user name and assign
            if !newResults.isEmpty {
                if people.isEmpty {
                    Section {
                        Button {
                            showAddPerson = true
                        } label: {
                            Label("Add a household member first", systemImage: "person.badge.plus")
                        }
                    } header: {
                        Text("People")
                    }
                }

                Section {
                    Text("Name the devices you want to track. Leave blank to skip a device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("New Devices (\(newResults.count))")
                }

                Section {
                    ForEach($rows) { $row in
                        DeviceRowView(row: $row, people: people, onAddPerson: { showAddPerson = true })
                    }
                }
            } else if !results.isEmpty {
                Section {
                    Text("All found devices are already registered.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Assign Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { saveAndFinish() }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Skip") { hasCompletedOnboarding = true }
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAddPerson) {
            AddPersonView()
        }
        .onAppear {
            // Rows only for new (unregistered) devices
            rows = newResults.map { DeviceRow(result: $0) }
        }
        .onChange(of: existingDevices.count) {
            // Refresh rows if new devices get saved (e.g. while sheet is open)
            rows = newResults.map { DeviceRow(result: $0) }
        }
    }

    private func saveAndFinish() {
        for row in rows {
            let name = row.label.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let device = Device(label: name, lastKnownIP: row.result.ip, hostname: row.result.hostname)
            context.insert(device)

            if let personID = row.selectedPersonID,
               let person = people.first(where: { $0.id == personID }) {
                device.person = person
                person.devices.append(device)
            }
        }
        hasCompletedOnboarding = true
    }
}

// MARK: - Row view

private struct DeviceRowView: View {
    @Binding var row: DeviceRow
    let people: [Person]
    let onAddPerson: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "wifi.circle.fill").foregroundStyle(.blue).font(.caption)
                Text(row.result.ip)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let hostname = row.result.hostname {
                    Text("· \(hostname)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            TextField("Name (e.g. Sarah's iPhone)", text: $row.label)
                .textFieldStyle(.roundedBorder)

            if !row.label.trimmingCharacters(in: .whitespaces).isEmpty {
                if people.isEmpty {
                    Button { onAddPerson() } label: {
                        Label("Add person to assign", systemImage: "person.badge.plus")
                            .font(.subheadline)
                    }
                } else {
                    Picker("Assign to", selection: $row.selectedPersonID) {
                        Text("Don't assign").tag(Optional<UUID>.none)
                        ForEach(people) { p in
                            Text("\(p.emoji) \(p.name)").tag(Optional(p.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Row model

struct DeviceRow: Identifiable {
    let id = UUID()
    let result: ScanResult
    var label: String = ""
    var selectedPersonID: UUID? = nil
}
