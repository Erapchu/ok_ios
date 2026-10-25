import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppStore {
    enum SessionState { case restoring, signedOut, connected, expired }
    private(set) var snapshot: SocialSnapshot?
    private(set) var savedKeys: Set<String> = []
    private(set) var isLoading = false
    private(set) var isConnecting = false
    private(set) var isLoadingMore = false
    private(set) var updatedAt: Date?
    private(set) var sessionState: SessionState = .restoring
    let isPreview: Bool
    var errorMessage: String?
    var connectionError: String?
    private var service: (any SocialService)?
    private var accountID: String?
    private var generation = UUID()
    private let vault: KeychainTokenStore
    private let transport: HTTPClient?
    private var friendOffset = 0

    init(service: (any SocialService)? = nil, vault: KeychainTokenStore = KeychainTokenStore(), transport: HTTPClient? = nil) {
        self.service = service
        self.vault = vault
        self.transport = transport
        self.isPreview = service != nil
        if service != nil { sessionState = .connected; accountID = "preview" }
    }

    private var cacheKey: String { isPreview ? "preview-v2" : "ok-v2:\(accountID ?? "")" }
    private var reactionPrefix: String { "\(cacheKey):" }

    func restore(context: ModelContext) async {
        if isPreview { await load(context: context); return }
        guard sessionState == .restoring else { return }
        do {
            guard let tokens = try await vault.read(), let id = tokens.accountID, !id.isEmpty else {
                sessionState = .signedOut; return
            }
            accountID = id
            service = OKSocialService(api: OKAPIClient(credentials: tokens, transport: transport))
            sessionState = .connected
            await load(context: context)
            if let expiry = tokens.expiresAt, expiry <= .now { sessionState = .expired }
        } catch {
            sessionState = .signedOut
            errorMessage = "Не удалось прочитать Keychain. Разблокируйте iPhone и перезапустите приложение."
        }
    }

    func connect(applicationKey: String, token: String, secret: String, context: ModelContext) async -> Bool {
        guard !isConnecting, !isPreview else { return false }
        isConnecting = true
        defer { isConnecting = false }
        generation = UUID()
        let attempt = generation
        connectionError = nil
        var tokens = AuthTokens(accessToken: token.trimmingCharacters(in: .whitespacesAndNewlines), expiresAt: nil)
        tokens.applicationKey = applicationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        tokens.sessionSecretKey = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try OKAPIClient.validate(tokens)
            let live = OKSocialService(api: OKAPIClient(credentials: tokens, transport: transport))
            let fresh = try await live.fetchSnapshot()
            try Task.checkCancellation()
            guard generation == attempt else { return false }
            tokens.accountID = fresh.profile.id
            try await vault.save(tokens)
            guard generation == attempt else { try await vault.delete(); return false }
            accountID = fresh.profile.id
            service = live
            snapshot = fresh
            sessionState = .connected
            friendOffset = fresh.friends.count
            errorMessage = nil
            do {
                try persist(fresh, context: context)
                try readReactions(context: context)
            } catch {
                errorMessage = "Аккаунт подключён, но не удалось сохранить локальный кеш. Проверьте свободное место на iPhone."
            }
            return true
        } catch {
            if !Task.isCancelled { connectionError = Self.message(error) }
            return false
        }
    }

    func load(context: ModelContext, refresh: Bool = false) async {
        guard !isLoading, let service else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let attempt = generation
        do {
            try readReactions(context: context)
            if !refresh {
                let records = try context.fetch(FetchDescriptor<CachedSnapshot>())
                if let cached = records.first(where: { $0.key == cacheKey }),
                   let decoded = try? JSONDecoder().decode(SocialSnapshot.self, from: cached.payload),
                   isPreview || decoded.profile.id == accountID {
                    snapshot = decoded
                    updatedAt = cached.updatedAt
                    friendOffset = decoded.friends.count
                    return
                }
            }
            let fresh = try await service.fetchSnapshot()
            try Task.checkCancellation()
            guard generation == attempt else { return }
            guard isPreview || fresh.profile.id == accountID else { throw OKAPIError.authentication }
            try persist(fresh, context: context)
            snapshot = fresh
            friendOffset = fresh.friends.count
            if !isPreview { sessionState = .connected }
        } catch {
            guard generation == attempt, !Task.isCancelled, !(error is CancellationError) else { return }
            if error as? OKAPIError == .authentication { sessionState = .expired }
            errorMessage = Self.message(error)
        }
    }

    func loadMorePhotos(context: ModelContext) async {
        guard !isLoadingMore, !isLoading, let service, let anchor = snapshot?.photoAnchor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let attempt = generation
        do {
            let page = try await service.fetchPhotos(anchor: anchor)
            try Task.checkCancellation()
            guard generation == attempt, var value = snapshot else { return }
            var seen = Set(value.photos.map(\.id))
            value.photos += page.photos.filter { seen.insert($0.id).inserted }
            value.photoAnchor = page.nextAnchor == anchor ? nil : page.nextAnchor
            value.totalPhotoCount = page.totalCount ?? value.totalPhotoCount
            try persist(value, context: context)
            snapshot = value
        } catch { report(error, attempt: attempt) }
    }

    func loadMoreFriends(context: ModelContext) async {
        guard !isLoadingMore, !isLoading, let service, let current = snapshot,
              friendOffset < current.friendIDs.count else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let attempt = generation
        let ids = Array(current.friendIDs.dropFirst(friendOffset).prefix(OKSocialService.friendBatchSize))
        do {
            let friends = try await service.fetchFriends(ids: ids)
            try Task.checkCancellation()
            guard generation == attempt, var value = snapshot else { return }
            var seen = Set(value.friends.map(\.id))
            value.friends += friends.filter { seen.insert($0.id).inserted }
            let returned = Set(friends.map(\.id))
            let missing = Set(ids).subtracting(returned)
            value.friendIDs.removeAll { missing.contains($0) }
            try persist(value, context: context)
            snapshot = value
            friendOffset = value.friends.count
        } catch { report(error, attempt: attempt) }
    }

    func isSaved(_ key: String) -> Bool { savedKeys.contains(key) }

    func toggle(_ key: String, context: ModelContext) {
        do {
            let scoped = reactionPrefix + key
            let records = try context.fetch(FetchDescriptor<SavedReaction>())
            if let record = records.first(where: { $0.key == scoped }) { context.delete(record) }
            else { context.insert(SavedReaction(key: scoped)) }
            try context.save()
            if savedKeys.contains(key) { savedKeys.remove(key) } else { savedKeys.insert(key) }
        } catch {
            context.rollback()
            errorMessage = "Не удалось сохранить изменение. Попробуйте ещё раз."
        }
    }

    func clearCache(context: ModelContext) async {
        generation = UUID()
        do {
            try context.delete(model: CachedSnapshot.self)
            try context.save()
            await MediaCache.shared.clear()
            updatedAt = nil
        } catch {
            context.rollback()
            errorMessage = "Не удалось очистить кеш."
        }
    }

    func signOut(context: ModelContext) async {
        guard !isPreview else { return }
        generation = UUID()
        do { try await vault.delete() }
        catch { errorMessage = "Не удалось удалить токены из Keychain. Повторите выход."; return }
        snapshot = nil
        service = nil
        accountID = nil
        savedKeys = []
        updatedAt = nil
        sessionState = .signedOut
        do {
            try context.delete(model: CachedSnapshot.self)
            try context.delete(model: SavedReaction.self)
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "Сессия завершена, но не удалось очистить локальный кеш."
        }
        await MediaCache.shared.clear()
    }

    private func readReactions(context: ModelContext) throws {
        savedKeys = Set(try context.fetch(FetchDescriptor<SavedReaction>())
            .map(\.key).filter { $0.hasPrefix(reactionPrefix) }.map { String($0.dropFirst(reactionPrefix.count)) })
    }

    private func persist(_ value: SocialSnapshot, context: ModelContext) throws {
        do {
            let payload = try JSONEncoder().encode(value)
            let now = Date.now
            if let record = try context.fetch(FetchDescriptor<CachedSnapshot>()).first(where: { $0.key == cacheKey }) {
                record.payload = payload; record.updatedAt = now
            } else { context.insert(CachedSnapshot(payload: payload, updatedAt: now, key: cacheKey)) }
            try context.save()
            updatedAt = now
        } catch { context.rollback(); throw error }
    }

    private func report(_ error: Error, attempt: UUID) {
        guard attempt == generation, !Task.isCancelled, !(error is CancellationError) else { return }
        if error as? OKAPIError == .authentication { sessionState = .expired }
        errorMessage = Self.message(error)
    }

    private static func message(_ error: Error) -> String {
        if let apiError = error as? OKAPIError { return apiError.localizedDescription }
        return "Не удалось загрузить данные. Проверьте интернет-соединение. Сохранённые данные остаются доступны."
    }
}
