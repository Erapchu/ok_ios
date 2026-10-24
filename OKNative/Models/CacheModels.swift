import Foundation
import SwiftData

@Model
final class CachedSnapshot {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date = .now) {
        self.key = "demo-snapshot-v1"
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class SavedReaction {
    @Attribute(.unique) var key: String

    init(key: String) { self.key = key }
}

