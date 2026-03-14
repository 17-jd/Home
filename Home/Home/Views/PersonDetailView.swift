import SwiftUI

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(NetworkScanner.self) private var scanner

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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.label).font(.headline)
                                Text(device.lastKnownIP)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let ms = scanner.pingTimes[device.lastKnownIP] {
                                Text("\(ms)ms")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.green)
                            } else if scanner.respondingIPs.contains(device.lastKnownIP) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Text("away")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
