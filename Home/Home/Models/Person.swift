import Foundation
import SwiftData

@Model
class Person {
    var id: UUID
    var name: String
    var emoji: String
    var isHome: Bool
    var lastSeenAt: Date?
    var lateCheckTime: Date?

    // Explicit inverse required — iOS 18 no longer auto-syncs both sides
    @Relationship(deleteRule: .cascade, inverse: \Device.person)
    var devices: [Device] = []

    init(name: String, emoji: String = "👤") {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.isHome = false
        self.lastSeenAt = nil
        self.lateCheckTime = nil
    }

    enum PresenceStatus {
        case home, away, unassigned
    }

    func presenceStatus(respondingIPs: Set<String>) -> PresenceStatus {
        if devices.isEmpty { return .unassigned }
        return devices.contains { respondingIPs.contains($0.lastKnownIP) } ? .home : .away
    }
}
