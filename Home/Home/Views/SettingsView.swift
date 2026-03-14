import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query var people: [Person]
    @Query var devices: [Device]

    @AppStorage("subnetBase") private var subnetBase = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @State private var showAddPerson = false
    @State private var showConfirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                // Network
                Section {
                    HStack {
                        Text("Subnet")
                        Spacer()
                        TextField("e.g. 10.0.0", text: $subnetBase)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    Button("Auto-detect") {
                        subnetBase = NetworkScanner.detectSubnet()
                    }
                } header: {
                    Text("Network")
                } footer: {
                    Text("First three parts of your router's IP (e.g. 10.0.0).")
                }

                // Household members
                Section {
                    ForEach(people) { person in
                        NavigationLink(destination: PersonDetailView(person: person)) {
                            HStack {
                                Text(person.emoji).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name).font(.headline)
                                    Text("\(person.devices.count) device\(person.devices.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(people[$0]) }
                    }

                    Button {
                        showAddPerson = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Household Members")
                }

                // Setup
                Section {
                    Button("Re-run Setup", role: .destructive) {
                        showConfirmWipe = true
                    }
                } footer: {
                    Text("Wipes all people and devices, then restarts the setup scan.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                EditButton()
            }
            .sheet(isPresented: $showAddPerson) {
                AddPersonView()
            }
            .confirmationDialog(
                "This will delete all people and devices and restart setup.",
                isPresented: $showConfirmWipe,
                titleVisibility: .visible
            ) {
                Button("Wipe & Re-run Setup", role: .destructive) {
                    wipeAndRestart()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func wipeAndRestart() {
        devices.forEach { context.delete($0) }
        people.forEach { context.delete($0) }
        try? context.save()
        hasCompletedOnboarding = false
    }
}
