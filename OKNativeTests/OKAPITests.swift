import XCTest
import SwiftData
@testable import OKNative

final class OKAPITests: XCTestCase {
    static func tokens(_ access: String = "test-access") -> AuthTokens {
        var value = AuthTokens(accessToken: access, expiresAt: nil)
        value.applicationKey = "test-public"
        value.sessionSecretKey = "test-session-secret"
        value.accountID = "42"
        return value
    }

    static func transport() -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OKFixtureProtocol.self]
        return HTTPClient(session: URLSession(configuration: config))
    }

    func testSigningAndTokenIsOnlyInPOSTBody() throws {
        let params = ["method": "users.getCurrentUser", "format": "json", "application_key": "test-public"]
        XCTAssertEqual(OKAPIClient.signature(params, secret: "test-session-secret"), "2808b6dc4a3baff953d1ae215f7848f0")
        let withToken = params.merging(["access_token": "never-signed", "sig": "previous"]) { _, new in new }
        XCTAssertEqual(OKAPIClient.signature(params, secret: "test-session-secret"), OKAPIClient.signature(withToken, secret: "test-session-secret"))
        let request = try OKAPIClient(credentials: Self.tokens()).request("users.getCurrentUser")
        XCTAssertEqual(request.url?.absoluteString, "https://api.ok.ru/fb.do")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertTrue(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)?.contains("access_token=test-access") == true)
        XCTAssertEqual(OKAPIClient.formEncoded(["x": "a+b=c &я"]), "x=a%2Bb%3Dc%20%26%D1%8F")
    }

    func testSessionAndPermissionErrorsInsideHTTP200() async throws {
        for (token, expected) in [("expired", OKAPIError.authentication), ("denied", .permission),
                                  ("invalid-session", .authentication), ("invalid-signature", .invalidCredentials)] {
            let api = OKAPIClient(credentials: Self.tokens(token), transport: Self.transport())
            do {
                let _: OKUser = try await api.call("users.getCurrentUser")
                XCTFail("An API error must not be decoded as user data")
            } catch {
                XCTAssertEqual(error as? OKAPIError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret-token-echo"))
            }
        }
    }

    func testSnapshotLoadsActualUserFriendsAndPhotoPage() async throws {
        let service = OKSocialService(api: OKAPIClient(credentials: Self.tokens(), transport: Self.transport()))
        let snapshot = try await service.fetchSnapshot()
        XCTAssertEqual(snapshot.profile.id, "42")
        XCTAssertEqual(snapshot.profile.name, "API User")
        XCTAssertEqual(snapshot.friends.map(\.id), ["7", "8"])
        XCTAssertEqual(snapshot.photos.first?.id, "9007199254740993")
        XCTAssertEqual(snapshot.photos.first?.asset, "https://example.invalid/photo.jpg")
        XCTAssertEqual(snapshot.photoAnchor, "next-page")
        XCTAssertTrue(snapshot.posts.isEmpty, "Live API must never return demo feed posts")
        XCTAssertTrue(snapshot.issues.isEmpty)
    }

    func testOptionalPermissionFailureDoesNotHideProfile() async throws {
        let service = OKSocialService(api: OKAPIClient(credentials: Self.tokens("photos-denied"), transport: Self.transport()))
        let snapshot = try await service.fetchSnapshot()
        XCTAssertEqual(snapshot.profile.id, "42")
        XCTAssertEqual(snapshot.friends.count, 2)
        XCTAssertTrue(snapshot.photos.isEmpty)
        XCTAssertEqual(snapshot.issues.map(\.section), ["photos"])
    }

    func testMissingCredentialsAreRejectedLocally() throws {
        XCTAssertThrowsError(try OKAPIClient.validate(AuthTokens(accessToken: "x", expiresAt: nil)))
    }

    func testOriginalExpiryDoesNotBlockServerExtendedToken() async throws {
        let saved = Self.tokens()
        let extended = AuthTokens(accessToken: saved.accessToken, expiresAt: .distantPast,
                                  applicationKey: saved.applicationKey, sessionSecretKey: saved.sessionSecretKey)
        let api = OKAPIClient(credentials: extended, transport: Self.transport())
        let user: OKUser = try await api.call("users.getCurrentUser")
        XCTAssertEqual(user.id, "42")
    }

    func testCurrentPhotoResponseSchema() throws {
        let data = Data(#"{"photos":[{"id":"5","text":"Caption","pic640x480":"https://example.invalid/p.jpg"}],"has_more":true,"anchor":"next","totalCount":100}"#.utf8)
        let result = try JSONDecoder().decode(OKPhotosResponse.self, from: data)
        XCTAssertEqual(result.photos.first?.id, "5")
        XCTAssertEqual(result.anchor, "next")
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.totalCount, 100)
    }
}

@MainActor
final class LiveSessionTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: CachedSnapshot.self, SavedReaction.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func cachedContainer() throws -> ModelContainer {
        let storage = try container()
        var profile = UserProfile(name: "Cached", city: "", bio: "", avatar: "")
        profile.id = "42"
        let snapshot = SocialSnapshot(profile: profile, friends: [], photos: [], posts: [])
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(snapshot), key: "ok-v2:42"))
        try storage.mainContext.save()
        return storage
    }

    func testRestoreAcceptsServerExtendedTokenWithOriginalExpiryInPast() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        let tokens = AuthTokens(accessToken: "test-access", expiresAt: .distantPast,
                                applicationKey: "test-public", sessionSecretKey: "test-session-secret", accountID: "42")
        try await vault.save(tokens)
        defer { Task { try? await vault.delete() } }
        let storage = try container()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        await store.restore(context: storage.mainContext)
        XCTAssertEqual(store.sessionState, .connected)
        XCTAssertEqual(store.snapshot?.profile.name, "API User")
        XCTAssertNil(store.errorMessage)
    }

    func testCachedLaunchChecksSessionWithServerAndStaysConnectedOffline() async throws {
        for (token, expected) in [("test-access", AppStore.SessionState.connected),
                                  ("expired", .expired), ("invalid-session", .expired), ("offline", .connected)] {
            let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
            let tokens = AuthTokens(accessToken: token, expiresAt: .distantPast,
                                    applicationKey: "test-public", sessionSecretKey: "test-session-secret", accountID: "42")
            try await vault.save(tokens)
            let storage = try cachedContainer()
            let store = AppStore(vault: vault, transport: OKAPITests.transport())
            await store.restore(context: storage.mainContext)
            XCTAssertEqual(store.sessionState, expected, token)
            XCTAssertEqual(store.snapshot?.profile.name, "Cached", token)
            let saved = try await vault.read()
            XCTAssertEqual(saved, tokens, "Session checks must preserve stored credentials")
            if expected == .connected { XCTAssertNil(store.errorMessage, token) }
            else { XCTAssertNotNil(store.errorMessage, token) }
            try await vault.delete()
        }
    }

    func testLateSessionRejectionCannotChangeSignedOutState() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        try await vault.save(OKAPITests.tokens("slow-session-rejected"))
        let storage = try cachedContainer()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        let restore = Task { await store.restore(context: storage.mainContext) }
        try await Task.sleep(for: .milliseconds(30))
        await store.signOut(context: storage.mainContext)
        await restore.value
        XCTAssertEqual(store.sessionState, .signedOut)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.errorMessage)
    }

    func testNormalLaunchHasNoDemoFallback() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        let storage = try container()
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(DemoSocialService.snapshot)))
        await store.restore(context: storage.mainContext)
        XCTAssertEqual(store.sessionState, .signedOut)
        XCTAssertFalse(store.isPreview)
        XCTAssertNil(store.snapshot)
    }

    func testConnectValidatesSessionAndLogoutDeletesPrivateData() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        let storage = try container()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        let connected = await store.connect(applicationKey: "test-public", token: "test-access", secret: "test-session-secret", context: storage.mainContext)
        XCTAssertTrue(connected)
        let saved = try await vault.read()
        XCTAssertEqual(saved?.accountID, "42")
        store.toggle("photo:9007199254740993", context: storage.mainContext)
        await store.signOut(context: storage.mainContext)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.sessionState, .signedOut)
        let deleted = try await vault.read()
        XCTAssertNil(deleted)
        XCTAssertEqual(try storage.mainContext.fetchCount(FetchDescriptor<CachedSnapshot>()), 0)
        XCTAssertEqual(try storage.mainContext.fetchCount(FetchDescriptor<SavedReaction>()), 0)
    }

    func testWrongAccountCacheIsNeverDisplayed() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        try await vault.save(OKAPITests.tokens())
        defer { Task { try? await vault.delete() } }
        let storage = try container()
        // Even a record placed under the expected key must belong to the authenticated UID.
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(DemoSocialService.snapshot), key: "ok-v2:42"))
        try storage.mainContext.save()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        await store.restore(context: storage.mainContext)
        XCTAssertEqual(store.snapshot?.profile.id, "42")
        XCTAssertEqual(store.snapshot?.profile.name, "API User")
    }

    func testLateRefreshCannotRestoreSignedOutData() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        try await vault.save(OKAPITests.tokens("slow"))
        let storage = try container()
        var snapshot = DemoSocialService.snapshot
        var profile = UserProfile(name: "Cached", city: "", bio: "", avatar: "")
        profile.id = "42"
        snapshot = SocialSnapshot(profile: profile, friends: [], photos: [], posts: [])
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(snapshot), key: "ok-v2:42"))
        try storage.mainContext.save()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        await store.restore(context: storage.mainContext)
        let refresh = Task { await store.load(context: storage.mainContext, refresh: true) }
        try await Task.sleep(for: .milliseconds(30))
        await store.signOut(context: storage.mainContext)
        await refresh.value
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.sessionState, .signedOut)
        XCTAssertEqual(try storage.mainContext.fetchCount(FetchDescriptor<CachedSnapshot>()), 0)
    }

    func testPhotoPagingDeduplicatesAndStopsRepeatedAnchor() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        let storage = try container()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        let connected = await store.connect(applicationKey: "test-public", token: "test-access", secret: "test-session-secret", context: storage.mainContext)
        XCTAssertTrue(connected)
        await store.loadMorePhotos(context: storage.mainContext)
        XCTAssertEqual(store.snapshot?.photos.count, 1)
        XCTAssertNil(store.snapshot?.photoAnchor)
        await store.signOut(context: storage.mainContext)
    }

    func testFriendPagingAdvancesPastUnavailableUsers() async throws {
        let vault = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        try await vault.save(OKAPITests.tokens())
        let storage = try container()
        var profile = UserProfile(name: "Cached", city: "", bio: "", avatar: "")
        profile.id = "42"
        var snapshot = SocialSnapshot(profile: profile, friends: [], photos: [], posts: [])
        snapshot.friendIDs = ["deleted-a", "private-b"]
        snapshot.friendCursor = 0
        storage.mainContext.insert(CachedSnapshot(payload: try JSONEncoder().encode(snapshot), key: "ok-v2:42"))
        try storage.mainContext.save()
        let store = AppStore(vault: vault, transport: OKAPITests.transport())
        await store.restore(context: storage.mainContext)
        XCTAssertTrue(store.snapshot?.hasMoreFriends == true)
        await store.loadMoreFriends(context: storage.mainContext)
        XCTAssertFalse(store.snapshot?.hasMoreFriends == true)
        XCTAssertEqual(store.snapshot?.friendCursor, 2)
        XCTAssertTrue(store.snapshot?.friends.isEmpty == true)
        await store.signOut(context: storage.mainContext)
    }
}

private final class OKFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        }
        let components = URLComponents(string: "https://example.invalid/?" + String(data: data ?? Data(), encoding: .utf8)!)
        let fields = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, new in new })
        let token = fields["access_token"] ?? ""
        let method = fields["method"] ?? ""
        if token == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let payload: String
        if token == "slow-session-rejected" { payload = #"{"error_code":102}"# }
        else if token == "expired" { payload = #"{"error_code":102,"error_msg":"secret-token-echo"}"# }
        else if token == "invalid-session" { payload = #"{"error_code":103}"# }
        else if token == "invalid-signature" { payload = #"{"error_code":104}"# }
        else if token == "denied" || (token == "photos-denied" && method == "photos.getPhotos") { payload = #"{"error_code":10}"# }
        else {
            switch method {
            case "users.getCurrentUser": payload = #"{"uid":"42","name":"API User","location":{"city":"Moscow"},"pic128x128":"https://example.invalid/avatar.jpg"}"#
            case "friends.get": payload = #"["7",8]"#
            case "users.getInfo": payload = #"[{"uid":8,"name":"Friend B","online":"web"},{"uid":"7","name":"Friend A"}]"#
            case "photos.getPhotos": payload = #"{"photos":[{"photo":{"id":9007199254740993,"text":"Real photo","pic1024x768":"https://example.invalid/photo.jpg"}}],"hasMore":true,"anchor":"next-page","total_count":70}"#
            default: payload = #"{"error_code":3}"#
            }
        }
        if token == "slow" || token == "slow-session-rejected" {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { self.reply(payload) }
        } else { reply(payload) }
    }

    private func reply(_ text: String) {
        guard !lock.withLock({ stopped }), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { lock.withLock { stopped = true } }
}
