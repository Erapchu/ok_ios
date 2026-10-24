import XCTest
import SwiftData
@testable import OKNative

@MainActor
final class AppStoreTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: CachedSnapshot.self, SavedReaction.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testSnapshotAndReactionsSurviveNewStore() async throws {
        let storage = try container()
        let store = AppStore()
        await store.load(context: storage.mainContext)
        XCTAssertEqual(store.snapshot?.photos.count, 6)
        store.toggle("photo:lake", context: storage.mainContext)
        store.toggle("post:weekend", context: storage.mainContext)

        let restored = AppStore(service: FailingService())
        await restored.load(context: storage.mainContext)
        XCTAssertEqual(restored.snapshot?.profile.name, "Александр Морозов")
        XCTAssertTrue(restored.isSaved("photo:lake"))
        XCTAssertTrue(restored.isSaved("post:weekend"))
        XCTAssertNil(restored.errorMessage, "A valid cache should load without a service request")
    }

    func testRefreshFailureKeepsLoadedSnapshot() async throws {
        let storage = try container()
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(DemoSocialService.snapshot)))
        try storage.mainContext.save()
        let store = AppStore(service: FailingService())
        await store.load(context: storage.mainContext)
        await store.load(context: storage.mainContext, refresh: true)
        XCTAssertEqual(store.snapshot?.photos.count, 6)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testClearCachePreservesReactionsAndRebuildsSnapshot() async throws {
        let storage = try container()
        let store = AppStore()
        await store.load(context: storage.mainContext)
        store.toggle("photo:lake", context: storage.mainContext)
        store.clearCache(context: storage.mainContext)
        XCTAssertTrue(try storage.mainContext.fetch(FetchDescriptor<CachedSnapshot>()).isEmpty)
        XCTAssertTrue(store.isSaved("photo:lake"))
        XCTAssertNil(store.updatedAt)
        await store.load(context: storage.mainContext, refresh: true)
        XCTAssertEqual(try storage.mainContext.fetchCount(FetchDescriptor<CachedSnapshot>()), 1)
        XCTAssertTrue(store.isSaved("photo:lake"))
    }

    func testCorruptCacheIsReplacedAndReactionCanBeRemoved() async throws {
        let storage = try container()
        storage.mainContext.insert(CachedSnapshot(payload: Data("invalid".utf8)))
        try storage.mainContext.save()
        let store = AppStore()
        await store.load(context: storage.mainContext)
        XCTAssertNotNil(store.snapshot)
        XCTAssertNil(store.errorMessage)
        store.toggle("photo:lake", context: storage.mainContext)
        store.toggle("photo:lake", context: storage.mainContext)
        XCTAssertFalse(store.isSaved("photo:lake"))
        XCTAssertEqual(try storage.mainContext.fetchCount(FetchDescriptor<SavedReaction>()), 0)
    }

    func testCancellationDoesNotDisplayError() async throws {
        let storage = try container()
        let store = AppStore(service: CancelledService())
        await store.load(context: storage.mainContext)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }
}

private struct FailingService: SocialService {
    func fetchSnapshot() async throws -> SocialSnapshot { throw URLError(.notConnectedToInternet) }
}

private struct CancelledService: SocialService {
    func fetchSnapshot() async throws -> SocialSnapshot { throw CancellationError() }
}

