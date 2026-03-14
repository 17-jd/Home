import SwiftUI
import SwiftData

struct AddPersonView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "👤"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Emoji")
                        Spacer()
                        TextField("👤", text: $emoji)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("e.g. Sarah", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let person = Person(name: name, emoji: emoji.isEmpty ? "👤" : emoji)
                        context.insert(person)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
