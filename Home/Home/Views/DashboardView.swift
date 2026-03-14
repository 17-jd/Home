import SwiftUI
import SwiftData

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(NetworkScanner.self) private var scanner
    @Environment(\.modelContext)       private var context
    @Query var people:     [Person]
    @Query var allDevices: [Device]
    @AppStorage("subnetBase")          private var subnetBase         = ""
    @AppStorage("notifyArrivals")      private var notifyArrivals     = true
    @AppStorage("notifyDepartures")    private var notifyDepartures   = true

    @State private var assigningPerson:  Person?        = nil
    @State private var checkingPersonID: String?        = nil
    /// Consecutive failed presence checks per person — notification fires on 2nd miss.
    @State private var awayStrikes:      [String: Int]  = [:]

    private var respondingIPs: Set<String> { scanner.respondingIPs }
    private var homeCount:    Int { people.filter { $0.presenceStatus(respondingIPs: respondingIPs) == .home }.count }
    private var trackedCount: Int { people.filter { !$0.devices.isEmpty }.count }
    private var unassigned: [ScanResult] {
        let taken = Set(allDevices.map { $0.lastKnownIP })
        return scanner.results.filter { !taken.contains($0.ip) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        presenceHeader
                        peopleGrid
                        Spacer(minLength: 160)
                    }
                }
                scanFooter
            }
            .navigationTitle("Who's Home")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $assigningPerson) { person in
                AssignDeviceSheet(person: person, unassignedResults: unassigned)
            }
        }
        .task {
            if subnetBase.isEmpty { subnetBase = NetworkScanner.detectSubnet() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(90))
                let ips    = allDevices.map { $0.lastKnownIP }
                let subnet = subnetBase.isEmpty ? NetworkScanner.detectSubnet() : subnetBase
                guard !ips.isEmpty else { continue }
                await scanner.quickPresenceCheck(deviceIPs: ips, subnet: subnet)
                updatePresence(notify: true)
            }
        }
    }

    // MARK: Presence header

    private var presenceHeader: some View {
        ZStack {
            LinearGradient(
                colors: homeCount > 0
                    ? [Color.green.opacity(0.09), Color(.systemBackground)]
                    : [Color.blue.opacity(0.05), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 6) {
                if trackedCount == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.blue.gradient)
                        Text("Add people in Settings")
                            .font(.headline).foregroundStyle(.secondary)
                    }.padding(.vertical, 40)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(homeCount)")
                            .font(.system(size: 80, weight: .black, design: .rounded))
                            .foregroundStyle(homeCount > 0 ? Color.green : Color.primary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.4), value: homeCount)
                        Text("/ \(trackedCount)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 10)
                    }
                    Text(homeCount == 1 ? "person home" : "people home")
                        .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    if let last = scanner.lastScannedAt {
                        Text("Scanned \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 32).padding(.horizontal, 20)
        }
    }

    // MARK: People grid

    @ViewBuilder
    private var peopleGrid: some View {
        if people.isEmpty {
            ContentUnavailableView(
                "No people yet", systemImage: "person.2",
                description: Text("Add household members in Settings")
            ).padding(.top, 48)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(people) { person in
                    PersonCard(
                        person:    person,
                        status:    person.presenceStatus(respondingIPs: respondingIPs),
                        pingMs:    person.devices.compactMap { scanner.pingTimes[$0.lastKnownIP] }.min(),
                        isChecking: checkingPersonID == person.id.uuidString
                    ) {
                        if person.devices.isEmpty {
                            assigningPerson = person
                        } else {
                            Task { await checkPerson(person) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: Scan footer

    private var scanFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            if scanner.isScanning {
                ScanRadarView(progress: scanner.progress)
                    .padding(.vertical, 20)
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom).combined(with: .opacity),
                        removal:   .push(from: .top).combined(with: .opacity)
                    ))
            } else {
                VStack(spacing: 8) {
                    Button {
                        Task { await runScan() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi")
                            Text("Scan Network").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.35), radius: 10, y: 4)
                    }
                    .padding(.horizontal, 20)

                    if scanner.isCheckingPresence {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.65)
                            Text("Checking presence…")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 16)
                .transition(.asymmetric(
                    insertion: .push(from: .bottom).combined(with: .opacity),
                    removal:   .push(from: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(duration: 0.45), value: scanner.isScanning)
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func runScan() async {
        let subnet = subnetBase.isEmpty ? NetworkScanner.detectSubnet() : subnetBase
        await scanner.scan(subnet: subnet)
        reconcileDeviceIPs()
        updatePresence(notify: true)
    }

    /// Tap-to-check: ping only this person's devices immediately.
    private func checkPerson(_ person: Person) async {
        guard checkingPersonID == nil, !scanner.isScanning else { return }
        checkingPersonID = person.id.uuidString
        defer { checkingPersonID = nil }
        let ips    = person.devices.map { $0.lastKnownIP }
        let subnet = subnetBase.isEmpty ? NetworkScanner.detectSubnet() : subnetBase
        guard !ips.isEmpty else { return }
        await scanner.quickPresenceCheck(deviceIPs: ips, subnet: subnet)
        updatePresence(notify: false)   // manual check — no notification
    }

    /// Update presence state. Notifications require 2 consecutive failed checks
    /// to avoid false "left home" alerts for sleeping iPhones.
    private func updatePresence(notify: Bool) {
        for person in people {
            let pid       = person.id.uuidString
            let status    = person.presenceStatus(respondingIPs: respondingIPs)
            let wasHome   = person.isHome
            let isNowHome = (status == .home)

            person.isHome = isNowHome
            if isNowHome { person.lastSeenAt = Date() }

            if notify {
                if isNowHome {
                    awayStrikes[pid] = 0
                    if !wasHome && notifyArrivals {
                        NotificationManager.shared.personArrived(name: person.name, emoji: person.emoji)
                    }
                } else {
                    let strikes = (awayStrikes[pid] ?? 0) + 1
                    awayStrikes[pid] = strikes
                    // Only fire departure notification after 2nd consecutive failed check
                    if strikes == 2 && notifyDepartures {
                        NotificationManager.shared.personLeft(name: person.name, emoji: person.emoji)
                    }
                }
            }
        }
        try? context.save()
    }

    private func reconcileDeviceIPs() {
        var hostnameToIP = [String: String]()
        for r in scanner.results { if let h = r.hostname { hostnameToIP[h] = r.ip } }
        let seenIPs = Set(scanner.results.map { $0.ip })
        for device in allDevices {
            guard !seenIPs.contains(device.lastKnownIP) else { continue }
            if let h = device.hostname, let newIP = hostnameToIP[h] { device.lastKnownIP = newIP }
        }
        try? context.save()
    }
}

// MARK: - Radar scan animation

private struct ScanRadarView: View {
    let progress: Double

    @State private var sweep:  Double = 0
    @State private var pulse:  Double = 1.0

    private var phaseLabel: String {
        switch progress {
        case 0..<0.25: return "Waking devices…"
        case 0.25..<0.50: return "Reading ARP table…"
        case 0.50..<0.65: return "Second sweep…"
        case 0.65..<0.85: return "Verifying with ping…"
        default:           return "Enriching results…"
        }
    }

    var body: some View {
        HStack(spacing: 28) {
            // Radar visual
            ZStack {
                // Outer rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.blue.opacity(0.18 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: 50 + CGFloat(i) * 28)
                        .scaleEffect(pulse)
                        .animation(
                            .easeInOut(duration: 1.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.25),
                            value: pulse
                        )
                }
                // Progress arc (outer)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.blue.opacity(0.25),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 108)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
                // Rotating sweep
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        AngularGradient(colors: [.clear, .blue.opacity(0.9)],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(80)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 108)
                    .rotationEffect(.degrees(sweep))
                // Center
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "wifi")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers)
            }
            .frame(width: 120, height: 120)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { sweep = 360 }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true))  { pulse = 1.06 }
            }

            // Phase info
            VStack(alignment: .leading, spacing: 6) {
                Text(phaseLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .animation(.easeInOut(duration: 0.3), value: phaseLabel)
                    .contentTransition(.interpolate)

                // Segmented progress bar
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { seg in
                        let filled = progress >= Double(seg) / 4.0 + 0.01
                        Capsule()
                            .fill(filled ? Color.blue : Color.blue.opacity(0.15))
                            .frame(height: 4)
                            .animation(.easeInOut(duration: 0.4), value: filled)
                    }
                }
                .frame(maxWidth: 160)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Person card

private struct PersonCard: View {
    let person:     Person
    let status:     Person.PresenceStatus
    var pingMs:     Int?    = nil
    var isChecking: Bool    = false
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Avatar
                ZStack {
                    if status == .home {
                        Circle()
                            .stroke(
                                LinearGradient(colors: [.green, .mint],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2.5
                            )
                            .frame(width: 66, height: 66)
                    }
                    Circle()
                        .fill(cardBg)
                        .frame(width: 56, height: 56)
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(statusColor)
                    } else {
                        Text(person.emoji).font(.system(size: 26))
                    }
                }

                Text(person.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Status pill
                HStack(spacing: 5) {
                    if isChecking {
                        Text("Checking…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(statusLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(borderGradient, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(isChecking ? 0.97 : 1.0)
        .animation(.spring(duration: 0.3), value: isChecking)
    }

    private var statusColor: Color {
        switch status {
        case .home:       return .green
        case .away:       return .secondary
        case .unassigned: return .orange
        }
    }
    private var cardBg: Color {
        status == .home ? .green.opacity(0.12) : .secondary.opacity(0.1)
    }
    private var shadowColor: Color {
        status == .home ? .green.opacity(0.1) : .black.opacity(0.04)
    }
    private var borderGradient: LinearGradient {
        status == .home
            ? LinearGradient(colors: [.green.opacity(0.45), .mint.opacity(0.2)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
    }
    private var statusLabel: String {
        switch status {
        case .home:       return pingMs.map { "\($0)ms" } ?? "Home"
        case .away:       return "Away"
        case .unassigned: return "Assign device"
        }
    }
}

// MARK: - Assign device sheet

struct AssignDeviceSheet: View {
    let person:           Person
    let unassignedResults: [ScanResult]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if unassignedResults.isEmpty {
                    ContentUnavailableView(
                        "No unassigned devices", systemImage: "wifi.slash",
                        description: Text("Tap Scan Network first, or all found devices are already assigned.")
                    )
                } else {
                    List(unassignedResults) { result in
                        Button { assign(result) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.hostname ?? result.ip).font(.headline)
                                    if result.hostname != nil {
                                        Text(result.ip).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    if let ms = result.pingMs {
                                        Text("\(ms)ms").font(.caption).foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue).font(.title3)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assign to \(person.emoji) \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }

    private func assign(_ result: ScanResult) {
        let device = Device(label: result.hostname ?? result.ip,
                            lastKnownIP: result.ip, hostname: result.hostname)
        context.insert(device)
        device.person = person
        person.devices.append(device)
        try? context.save()
        dismiss()
    }
}
