import Foundation

struct SocialSnapshot: Codable, Sendable {
    let profile: UserProfile
    var friends: [SocialFriend]
    var photos: [SocialPhoto]
    let posts: [FeedPost]
    var friendIDs: [String] = []
    var friendCursor: Int? = nil
    var photoAnchor: String? = nil
    var totalPhotoCount: Int? = nil
    var issues: [SectionIssue] = []

    var totalFriends: Int { max(friendIDs.count, friends.count) }
    var hasMoreFriends: Bool { (friendCursor ?? friends.count) < friendIDs.count }
}

struct UserProfile: Codable, Sendable {
    var id: String = "preview"
    let name: String
    let city: String
    let bio: String
    let avatar: String
    var profileURL: String? = nil
}

struct SocialFriend: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let avatar: String
    let isOnline: Bool
}

struct SocialPhoto: Codable, Identifiable, Hashable, Sendable {
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

struct SectionIssue: Codable, Identifiable, Sendable {
    let section: String
    let message: String
    var id: String { section }
}

struct PhotoPage: Sendable {
    let photos: [SocialPhoto]
    let nextAnchor: String?
    let totalCount: Int?
}

