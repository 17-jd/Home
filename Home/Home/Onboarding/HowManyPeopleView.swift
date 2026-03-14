import SwiftUI
import SwiftData

struct HowManyPeopleView: View {
    @Environment(OnboardingCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    @State private var entries: [PersonEntry] = [
        PersonEntry(index: 0),
        PersonEntry(index: 1),
    ]

    private var canContinue: Bool {
        entries.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("Add everyone who lives here. You'll assign their devices on the next screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Who lives here?")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.bottom, 4)
                }

                Section {
                    ForEach($entries) { $entry in
                        HStack(spacing: 12) {
                            TextField("😀", text: $entry.emoji)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .font(.title2)
                                .onChange(of: entry.emoji) { _, new in
                                    // Keep only the last typed character (emoji)
                                    if new.count > 2 {
                                        entry.emoji = String(new.suffix(1))
                                    }
                                }

                            TextField("Name", text: $entry.name)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        guard entries.count > 1 else { return }
                        entries.remove(atOffsets: offsets)
                    }

                    Button {
                        entries.append(PersonEntry(index: entries.count))
                    } label: {
                        Label("Add Person", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Text("Household Members")
                } footer: {
                    Text("Swipe left to remove. Tap the emoji to change it.")
                }
            }

            Button {
                saveAndContinue()
            } label: {
                Text("Next — Scan Network")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinue ? Color.blue : Color.secondary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canContinue)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .navigationTitle("Your Household")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }

    private func saveAndContinue() {
        for entry in entries {
            let name = entry.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let emoji = entry.emoji.isEmpty ? "👤" : entry.emoji
            let person = Person(name: name, emoji: emoji)
            context.insert(person)
        }
        try? context.save()
        coordinator.push(.scanning)
    }
}

struct PersonEntry: Identifiable {
    let id = UUID()
    var name: String = ""
    var emoji: String

    private static let defaultEmojis = ["👤","👩","👨","👧","👦","👴","👵","🧑","🧒","🧔"]

    init(index: Int) {
        self.emoji = PersonEntry.defaultEmojis[index % PersonEntry.defaultEmojis.count]
    }
}
