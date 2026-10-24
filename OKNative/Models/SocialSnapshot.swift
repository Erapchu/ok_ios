import Foundation

struct SocialSnapshot: Codable, Sendable {
    let profile: UserProfile
    let friends: [DemoFriend]
    let photos: [DemoPhoto]
    let posts: [FeedPost]
}

struct UserProfile: Codable, Sendable {
    let name: String
    let city: String
    let bio: String
    let avatar: String
}

struct DemoFriend: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let avatar: String
    let isOnline: Bool
}

struct DemoPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let location: String
    let asset: String
    let album: String
}

struct FeedPost: Codable, Identifiable, Sendable {
    let id: String
    let author: String
    let avatar: String
    let date: String
    let text: String
    let photoID: String
    let likes: Int
}

