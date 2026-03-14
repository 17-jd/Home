import SwiftUI

struct PersonDetailView: View {
    @Bindable var person: Person

    var body: some View {
        Form {
            Section("Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $person.name)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Emoji")
                    Spacer()
                    TextField("Emoji", text: $person.emoji)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Devices (\(person.devices.count))") {
                if person.devices.isEmpty {
                    Text("No devices assigned yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(person.devices) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.label).font(.headline)
                            Text(device.lastKnownIP)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
