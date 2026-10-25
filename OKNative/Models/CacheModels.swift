import Foundation
import SwiftData

@Model
final class CachedSnapshot {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date = .now, key: String = "preview-v2") {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class SavedReaction {
    @Attribute(.unique) var key: String

    init(key: String) { self.key = key }
}

