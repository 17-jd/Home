import Foundation
import SwiftData

@Model
class Device {
    var id: UUID
    var label: String
    var lastKnownIP: String
    var hostname: String?
    var lastSeenAt: Date?
    // Inverse is declared on Person.devices — do NOT add @Relationship here
    var person: Person?

    init(label: String, lastKnownIP: String, hostname: String? = nil) {
        self.id = UUID()
        self.label = label
        self.lastKnownIP = lastKnownIP
        self.hostname = hostname
        self.lastSeenAt = nil
        self.person = nil
    }
}
