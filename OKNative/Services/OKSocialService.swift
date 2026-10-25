import Foundation

struct OKSocialService: SocialService {
    let api: OKAPIClient
    static let friendBatchSize = 50

    func fetchSnapshot() async throws -> SocialSnapshot {
        let user: OKUser = try await api.call("users.getCurrentUser", parameters: [
            "fields": "uid,name,first_name,last_name,location,current_status,pic128x128,pic320min,url_profile"
        ])
        guard !user.id.isEmpty else { throw OKAPIError.invalidResponse }
        async let friendsResult = optionalFriends()
        async let photosResult = optionalPhotos()
        let (friends, photos) = try await (friendsResult, photosResult)
        var snapshot = SocialSnapshot(profile: user.profile, friends: friends.people, photos: photos.page.photos, posts: [])
        snapshot.friendIDs = friends.ids
        snapshot.photoAnchor = photos.page.nextAnchor
        snapshot.totalPhotoCount = photos.page.totalCount
        snapshot.issues = [friends.issue, photos.issue].compactMap { $0 }
        return snapshot
    }

    func fetchFriends(ids: [String]) async throws -> [SocialFriend] {
        guard !ids.isEmpty else { return [] }
        let users: [OKUser] = try await api.call("users.getInfo", parameters: [
            "uids": ids.joined(separator: ","),
            "fields": "uid,name,first_name,last_name,location,pic128x128,pic320min,online"
        ])
        let byID = Dictionary(users.map { ($0.id, $0.friend) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func fetchPhotos(anchor: String) async throws -> PhotoPage { try await photoPage(anchor: anchor) }

    private func photoPage(anchor: String? = nil) async throws -> PhotoPage {
        var fields = ["count": "50", "detectTotalCount": "true", "mark_as_read": "false",
                      "fields": "photo.id,photo.text,photo.pic640x480,photo.pic1024x768"]
        fields["anchor"] = anchor
        let response: OKPhotosResponse = try await api.call("photos.getPhotos", parameters: fields)
        return PhotoPage(photos: response.photos.map(\.model),
                         nextAnchor: response.hasMore ? response.anchor : nil, totalCount: response.totalCount)
    }

    private func optionalFriends() async throws -> (ids: [String], people: [SocialFriend], issue: SectionIssue?) {
        var ids: [String] = []
        do {
            let raw: [OKScalar] = try await api.call("friends.get")
            var seen: Set<String> = []
            ids = raw.map(\.string).filter { !$0.isEmpty && seen.insert($0).inserted }
            let people = try await fetchFriends(ids: Array(ids.prefix(Self.friendBatchSize)))
            return (ids, people, nil)
        } catch {
            try Task.checkCancellation()
            if error as? OKAPIError == .authentication { throw error }
            return (ids, [], SectionIssue(section: "friends", message: Self.message(error)))
        }
    }

    private func optionalPhotos() async throws -> (page: PhotoPage, issue: SectionIssue?) {
        do { return (try await photoPage(), nil) }
        catch {
            try Task.checkCancellation()
            if error as? OKAPIError == .authentication { throw error }
            return (PhotoPage(photos: [], nextAnchor: nil, totalCount: nil),
                    SectionIssue(section: "photos", message: Self.message(error)))
        }
    }

    static func message(_ error: Error) -> String {
        if let apiError = error as? OKAPIError { return apiError.localizedDescription }
        return "Не удалось загрузить раздел. Проверьте соединение и обновите данные."
    }
}

/// OK IDs can appear as JSON strings or numbers. Never decode them through Double.
struct OKScalar: Decodable, Sendable {
    let string: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let n = try? c.decode(Int64.self) { string = String(n) }
        else if let b = try? c.decode(Bool.self) { string = String(b) }
        else { throw OKAPIError.invalidResponse }
    }
}

struct OKLocation: Decodable, Sendable {
    let city: String?
    let countryName: String?
    let country: String?
    var description: String { [city, countryName ?? country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct OKUser: Decodable, Sendable {
    let uid: OKScalar
    let name: String?
    let first_name: String?
    let last_name: String?
    let location: OKLocation?
    let current_status: String?
    let pic128x128: String?
    let pic320min: String?
    let online: OKScalar?
    let url_profile: String?

    var id: String { uid.string }
    var displayName: String {
        if let name, !name.isEmpty { return name }
        let parts = [first_name, last_name].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? "Пользователь ОК" : parts
    }
    var avatar: String { pic320min ?? pic128x128 ?? "" }
    var profile: UserProfile {
        var value = UserProfile(name: displayName, city: location?.description ?? "",
                                bio: current_status ?? "", avatar: avatar)
        value.id = id
        value.profileURL = url_profile ?? "https://ok.ru/profile/\(id)"
        return value
    }
    var friend: SocialFriend {
        SocialFriend(id: id, name: displayName, detail: location?.description ?? "",
                     avatar: avatar, isOnline: ["true", "web", "mob", "mobile"].contains(online?.string.lowercased() ?? ""))
    }
}

struct OKPhotosResponse: Decodable, Sendable {
    let photos: [OKPhoto]
    let anchor: String?
    let hasMore: Bool
    let totalCount: Int?
    enum CodingKeys: String, CodingKey { case photos, anchor, pagingAnchor, hasMore, has_more, total_count, totalCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photos = try c.decode([OKPhoto].self, forKey: .photos)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? c.decodeIfPresent(String.self, forKey: .pagingAnchor)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? c.decodeIfPresent(Bool.self, forKey: .has_more) ?? false
        totalCount = try c.decodeIfPresent(Int.self, forKey: .total_count) ?? c.decodeIfPresent(Int.self, forKey: .totalCount)
    }
}

struct OKPhoto: Decodable, Sendable {
    let id: String
    let text: String
    let url: String
    enum CodingKeys: String, CodingKey { case photo, id, text, caption, pic1024x768, pic640x480, standard_url }
    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try outer.decodeIfPresent(OKPhoto.self, forKey: .photo) { self = nested; return }
        id = try outer.decode(OKScalar.self, forKey: .id).string
        text = try outer.decodeIfPresent(String.self, forKey: .text) ?? outer.decodeIfPresent(String.self, forKey: .caption) ?? ""
        url = try outer.decodeIfPresent(String.self, forKey: .pic1024x768)
            ?? outer.decodeIfPresent(String.self, forKey: .pic640x480)
            ?? outer.decodeIfPresent(String.self, forKey: .standard_url) ?? ""
    }
    var model: SocialPhoto {
        SocialPhoto(id: id, title: text.isEmpty ? "Фотография" : text,
                    location: "", asset: url, album: "Личные фотографии")
    }
}
