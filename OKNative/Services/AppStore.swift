import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppStore {
    private(set) var snapshot: SocialSnapshot?
    private(set) var savedKeys: Set<String> = []
    private(set) var isLoading = false
    private(set) var updatedAt: Date?
    var errorMessage: String?
    private let service: any SocialService

    init(service: any SocialService = DemoSocialService()) {
        self.service = service
    }

    func load(context: ModelContext, refresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            savedKeys = Set(try context.fetch(FetchDescriptor<SavedReaction>()).map(\.key))
            if !refresh, let cached = try context.fetch(FetchDescriptor<CachedSnapshot>()).first {
                // A bad cache should not prevent a fresh service response.
                if let decoded = try? JSONDecoder().decode(SocialSnapshot.self, from: cached.payload) {
                    snapshot = decoded
                    updatedAt = cached.updatedAt
                    return
                }
            }
            let fresh = try await service.fetchSnapshot()
            try Task.checkCancellation()
            try persist(fresh, context: context)
            snapshot = fresh
        } catch is CancellationError {
            // The view can disappear while its task is running.
        } catch {
            errorMessage = snapshot == nil
                ? "Не удалось загрузить данные. Попробуйте ещё раз."
                : "Не удалось обновить данные. Показана сохранённая версия."
        }
    }

    func isSaved(_ key: String) -> Bool { savedKeys.contains(key) }

    func toggle(_ key: String, context: ModelContext) {
        do {
            let records = try context.fetch(FetchDescriptor<SavedReaction>())
            if let record = records.first(where: { $0.key == key }) {
                context.delete(record)
            } else {
                context.insert(SavedReaction(key: key))
            }
            try context.save()
            if savedKeys.contains(key) { savedKeys.remove(key) } else { savedKeys.insert(key) }
        } catch {
            context.rollback()
            errorMessage = "Не удалось сохранить изменение. Попробуйте ещё раз."
        }
    }

    func clearCache(context: ModelContext) {
        do {
            try context.delete(model: CachedSnapshot.self)
            try context.save()
            updatedAt = nil
        } catch {
            context.rollback()
            errorMessage = "Не удалось очистить кеш."
        }
    }

    private func persist(_ value: SocialSnapshot, context: ModelContext) throws {
        do {
            let payload = try JSONEncoder().encode(value)
            let now = Date.now
            if let record = try context.fetch(FetchDescriptor<CachedSnapshot>()).first {
                record.payload = payload
                record.updatedAt = now
            } else {
                context.insert(CachedSnapshot(payload: payload, updatedAt: now))
            }
            try context.save()
            updatedAt = now
        } catch {
            context.rollback()
            throw error
        }
    }
}

