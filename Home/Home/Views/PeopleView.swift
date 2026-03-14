import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Query var people: [Person]
    @State private var showAddPerson = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(people) { person in
                    NavigationLink(destination: PersonDetailView(person: person)) {
                        HStack {
                            Text(person.emoji).font(.title2)
                            VStack(alignment: .leading) {
                                Text(person.name).font(.headline)
                                Text("\(person.devices.count) device\(person.devices.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { context.delete(people[$0]) }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddPerson = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddPerson) {
                AddPersonView()
            }
        }
    }
}
