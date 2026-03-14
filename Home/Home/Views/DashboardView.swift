import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(NetworkScanner.self) private var scanner
    @Environment(\.modelContext) private var context
    @Query var people: [Person]
    @Query var allDevices: [Device]
    @AppStorage("subnetBase") private var subnetBase = ""

    @State private var assigningPerson: Person? = nil

    private var respondingIPs: Set<String> {
        scanner.respondingIPs
    }

    private var homeCount: Int {
        people.filter { $0.presenceStatus(respondingIPs: respondingIPs) == .home }.count
    }

    private var trackedCount: Int {
        people.filter { !$0.devices.isEmpty }.count
    }

    // Devices found in last scan that aren't assigned to anyone yet
    private var unassignedScanResults: [ScanResult] {
        let assignedIPs = Set(allDevices.map { $0.lastKnownIP })
        return scanner.results.filter { !assignedIPs.contains($0.ip) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary
                VStack(spacing: 4) {
                    if trackedCount == 0 {
                        Text("—")
                            .font(.system(size: 64, weight: .bold))
                        Text("scan to see who's home")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(homeCount) of \(trackedCount)")
                            .font(.system(size: 64, weight: .bold))
                        Text("people home")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 28)

                // People list
                if people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Add household members in Settings")
                    )
                    Spacer()
                } else {
                    List(people) { person in
                        PersonRow(
                            person: person,
                            status: person.presenceStatus(respondingIPs: respondingIPs),
                            onAssign: { assigningPerson = person }
                        )
                    }
                    .listStyle(.insetGrouped)
                }

                // Scan progress bar
                if scanner.isScanning {
                    ProgressView(value: scanner.progress)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                // Scan button
                Button {
                    Task { await runScan() }
                } label: {
                    Label(
                        scanner.isScanning ? "Scanning…" : "Scan Network",
                        systemImage: "wifi"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(scanner.isScanning ? Color.blue.opacity(0.5) : .blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(scanner.isScanning)
                .padding(.horizontal)
                .padding(.bottom, 4)

                if scanner.isCheckingPresence {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Checking…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                } else if let last = scanner.lastScannedAt {
                    Text("Last scanned \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Who's Home")
            .sheet(item: $assigningPerson) { person in
                AssignDeviceSheet(
                    person: person,
                    unassignedResults: unassignedScanResults
                )
            }
        }
        .task {
            if subnetBase.isEmpty {
                subnetBase = NetworkScanner.detectSubnet()
            }
            // Background presence loop — re-checks known device IPs every 90 s.
            // Much faster than a full scan (only probes assigned devices, ~1.5 s).
            // Keeps "who's home" accurate without the user tapping Scan Network.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(90))
                let ips = allDevices.map { $0.lastKnownIP }
                let subnet = subnetBase.isEmpty ? NetworkScanner.detectSubnet() : subnetBase
                guard !ips.isEmpty else { continue }
                await scanner.quickPresenceCheck(deviceIPs: ips, subnet: subnet)
                updatePresence()
            }
        }
    }

    private func runScan() async {
        let subnet = subnetBase.isEmpty ? NetworkScanner.detectSubnet() : subnetBase
        await scanner.scan(subnet: subnet)
        updatePresence()
    }

    private func updatePresence() {
        for person in people {
            let status = person.presenceStatus(respondingIPs: respondingIPs)
            person.isHome = (status == .home)
            if status == .home { person.lastSeenAt = Date() }
        }
        try? context.save()
    }
}

// MARK: - Person row

private struct PersonRow: View {
    let person: Person
    let status: Person.PresenceStatus
    let onAssign: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(person.emoji).font(.title2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline)
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            statusIcon
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if status == .unassigned { onAssign() }
        }
    }

    private var statusColor: Color {
        switch status {
        case .home:       return .green
        case .away:       return .secondary
        case .unassigned: return .orange
        }
    }

    private var statusLabel: String {
        switch status {
        case .home:       return "Home"
        case .away:       return "Away"
        case .unassigned: return "Tap to assign device"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .home:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
        case .away:
            Image(systemName: "xmark.circle")
                .font(.title2).foregroundStyle(.secondary)
        case .unassigned:
            Image(systemName: "questionmark.circle.fill")
                .font(.title2).foregroundStyle(.orange)
        }
    }
}

// MARK: - On-the-go assign sheet

struct AssignDeviceSheet: View {
    let person: Person
    let unassignedResults: [ScanResult]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if unassignedResults.isEmpty {
                    ContentUnavailableView(
                        "No unassigned devices",
                        systemImage: "wifi.slash",
                        description: Text("Tap Scan Network on the home screen first, or all found devices are already assigned.")
                    )
                } else {
                    List(unassignedResults) { result in
                        Button {
                            assign(result)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.hostname ?? result.ip).font(.headline)
                                    if result.hostname != nil {
                                        Text(result.ip)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assign to \(person.emoji) \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func assign(_ result: ScanResult) {
        let device = Device(
            label: result.hostname ?? result.ip,
            lastKnownIP: result.ip,
            hostname: result.hostname
        )
        context.insert(device)
        // Set both sides — iOS 18 requirement
        device.person = person
        person.devices.append(device)
        try? context.save()
        dismiss()
    }
}
