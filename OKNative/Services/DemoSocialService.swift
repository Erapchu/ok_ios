import Foundation

protocol SocialService: Sendable {
    func fetchSnapshot() async throws -> SocialSnapshot
    func fetchPhotos(anchor: String) async throws -> PhotoPage
    func fetchFriends(ids: [String]) async throws -> [SocialFriend]
}

extension SocialService {
    func fetchPhotos(anchor: String) async throws -> PhotoPage { throw OKAPIError.unsupported }
    func fetchFriends(ids: [String]) async throws -> [SocialFriend] { throw OKAPIError.unsupported }
}

struct DemoSocialService: SocialService {
    func fetchSnapshot() async throws -> SocialSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        return Self.snapshot
    }

    static let snapshot = SocialSnapshot(
        profile: UserProfile(
            name: "Александр Морозов", city: "Москва, Россия",
            bio: "Собираю моменты, а не вещи. Горы, дорога и люди рядом 🌿",
            avatar: "avatar-alex"
        ),
        friends: [
            SocialFriend(id: "anna", name: "Анна Смирнова", detail: "Москва", avatar: "avatar-anna", isOnline: true),
            SocialFriend(id: "mikhail", name: "Михаил Волков", detail: "Санкт-Петербург", avatar: "avatar-mike", isOnline: true),
            SocialFriend(id: "elena", name: "Елена Соколова", detail: "Казань", avatar: "avatar-elena", isOnline: false),
            SocialFriend(id: "dmitry", name: "Дмитрий Орлов", detail: "Москва", avatar: "avatar-alex", isOnline: false)
        ],
        photos: [
            SocialPhoto(id: "lake", title: "Там, где тихо", location: "Альпы", asset: "photo-lake", album: "Путешествия"),
            SocialPhoto(id: "peaks", title: "Выше облаков", location: "Горы", asset: "photo-peaks", album: "Путешествия"),
            SocialPhoto(id: "forest", title: "Выдохнуть", location: "Лесная тропа", asset: "photo-forest", album: "Моменты"),
            SocialPhoto(id: "valley", title: "Без спешки", location: "Долина", asset: "photo-valley", album: "Путешествия"),
            SocialPhoto(id: "coast", title: "Ещё один рассвет", location: "У озера", asset: "photo-coast", album: "Моменты"),
            SocialPhoto(id: "road", title: "Дорога к себе", location: "На природе", asset: "photo-road", album: "Моменты")
        ],
        posts: [
            FeedPost(id: "weekend", author: "Александр Морозов", avatar: "avatar-alex", date: "Сегодня в 10:24",
                     text: "Иногда лучший план на выходные — просто свернуть с привычной дороги. И оказаться здесь. 🏔️", photoID: "lake", likes: 24),
            FeedPost(id: "walk", author: "Анна Смирнова", avatar: "avatar-anna", date: "Вчера в 18:40",
                     text: "Немного лесной тишины в вашу ленту. Как же хорошо иногда никуда не торопиться.", photoID: "forest", likes: 18)
        ]
    )
}

