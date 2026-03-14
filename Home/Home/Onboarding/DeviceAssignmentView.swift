import SwiftUI
import SwiftData

// Replaces DeviceSetupView.
// Shows all found devices. User assigns each to a person or leaves unassigned.
struct DeviceAssignmentView: View {
    @Environment(OnboardingCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query var people: [Person]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var assignments: [DeviceAssignment] = []

    private var results: [ScanResult] { coordinator.scanner.results }

    var body: some View {
        List {
            Section {
                Text("Assign each device to a person. Leave it unassigned if you don't know whose it is — you can always assign later from the Home screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Found \(results.count) Devices") {
                ForEach($assignments) { $a in
                    DeviceAssignmentRow(assignment: $a, people: people)
                }
            }
        }
        .navigationTitle("Assign Devices")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
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
        .onAppear {
            assignments = results.map { DeviceAssignment(result: $0) }
        }
    }

    private func saveAndFinish() {
        for a in assignments {
            guard let personID = a.selectedPersonID,
                  let person = people.first(where: { $0.id == personID }) else { continue }

            let device = Device(
                label: a.result.hostname ?? a.result.ip,
                lastKnownIP: a.result.ip,
                hostname: a.result.hostname
            )
            context.insert(device)

            // Set BOTH sides — required since iOS 18 no longer auto-syncs inverse
            device.person = person
            person.devices.append(device)
        }
        try? context.save()
        hasCompletedOnboarding = true
    }
}

// MARK: - Row

private struct DeviceAssignmentRow: View {
    @Binding var assignment: DeviceAssignment
    let people: [Person]

    var assignedPerson: Person? {
        people.first { $0.id == assignment.selectedPersonID }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(assignedPerson == nil ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(assignedPerson?.emoji ?? "?")
                    .font(assignedPerson == nil ? .title3 : .body)
            }

            // IP + hostname
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.result.hostname ?? assignment.result.ip)
                    .font(.headline)
                    .lineLimit(1)
                if assignment.result.hostname != nil {
                    Text(assignment.result.ip)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Person picker
            Menu {
                Button("Unassigned") {
                    assignment.selectedPersonID = nil
                }
                Divider()
                ForEach(people) { person in
                    Button {
                        assignment.selectedPersonID = person.id
                    } label: {
                        Label("\(person.emoji) \(person.name)",
                              systemImage: assignment.selectedPersonID == person.id ? "checkmark" : "")
                    }
                }
            } label: {
                Text(assignedPerson.map { "\($0.emoji) \($0.name)" } ?? "Assign")
                    .font(.subheadline)
                    .foregroundStyle(assignedPerson == nil ? .orange : .blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(assignedPerson == nil ? Color.orange.opacity(0.12) : Color.blue.opacity(0.12))
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model

struct DeviceAssignment: Identifiable {
    let id = UUID()
    let result: ScanResult
    var selectedPersonID: UUID? = nil
}
