import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var selectedPhoto: SocialPhoto?

    var body: some View {
        Group {
            if let data = store.snapshot {
                ScrollView {
                    VStack(spacing: 26) {
                        profileCard(data)
                        ForEach(data.issues) { issue in
                            Label(issue.message, systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18).background(OKTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        }
                        friendsSection(data)
                        photosSection(data)
                        Label(store.isPreview ? "Демонстрационный профиль" : "Данные вашего аккаунта ОК",
                              systemImage: store.isPreview ? "sparkles" : "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).padding(.bottom, 28)
                }
                .refreshable { await store.load(context: context, refresh: true) }
            } else { LoadingContent() }
        }
        .background(OKTheme.background)
        .navigationTitle("Мой профиль").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Label("Настройки", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(photos: store.snapshot?.photos ?? [photo], initialID: photo.id)
        }
    }

    private func profileCard(_ data: SocialSnapshot) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Group {
                    if let photo = data.photos.first { MediaImage(reference: photo.asset) }
                    else {
                        LinearGradient(colors: [OKTheme.orange.opacity(0.75), .orange.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
            .frame(height: 150)
            .overlay(alignment: .topTrailing) {
                Label("Мой ОК", systemImage: "sparkle")
                    .font(.caption.weight(.medium)).padding(12)
                    .modifier(FloatingGlass()).padding(14)
            }
            VStack(spacing: 14) {
                Avatar(asset: data.profile.avatar, size: 104).padding(.top, -52)
                Text(data.profile.name).font(.title2.bold()).multilineTextAlignment(.center)
                if !data.profile.city.isEmpty {
                    Label(data.profile.city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !data.profile.bio.isEmpty {
                    Text(data.profile.bio).font(.subheadline).multilineTextAlignment(.center).lineSpacing(4)
                }
                if let url = data.profile.profileURL.flatMap(URL.init(string:)), url.scheme == "https" {
                    Link(destination: url) {
                        Label("Открыть в ОК", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.modifier(GlassActionStyle(prominent: true))
                }
                HStack {
                    NavigationLink { FriendsView() } label: {
                        statistic(data.issues.contains { $0.section == "friends" } && data.friendIDs.isEmpty ? "—" : data.totalFriends.formatted(), "Друзья")
                    }
                    Divider().frame(height: 32)
                    NavigationLink { PhotosView() } label: {
                        statistic(data.issues.contains { $0.section == "photos" } ? "—" : (data.totalPhotoCount ?? data.photos.count).formatted(), data.totalPhotoCount == nil && data.photoAnchor != nil ? "Фото загружено" : "Фотографии")
                    }
                }.buttonStyle(.plain).padding(.top, 6)
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .background(OKTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28)).padding(.top, 12)
    }

    private func statistic(_ value: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.bold()).foregroundStyle(.primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private func friendsSection(_ data: SocialSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Люди рядом", subtitle: "Ваши друзья в Одноклассниках")
                NavigationLink { FriendsView() } label: { Image(systemName: "arrow.up.right").padding(12) }
                    .modifier(GlassActionStyle()).accessibilityLabel("Все друзья")
            }
            if data.friends.isEmpty {
                Text(data.issues.contains { $0.section == "friends" } ? "Раздел пока недоступен" : "Здесь появятся ваши друзья")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(data.friends.prefix(10)) { friend in
                            NavigationLink { FriendDetailView(friend: friend) } label: {
                                VStack(spacing: 8) {
                                    Avatar(asset: friend.avatar, size: 58, online: friend.isOnline)
                                    Text(friend.name.components(separatedBy: " ").first ?? friend.name)
                                        .font(.caption).foregroundStyle(.primary).lineLimit(1)
                                }.frame(width: 66)
                            }.buttonStyle(.plain)
                        }
                    }.padding(3)
                }
            }
        }
    }

    private func photosSection(_ data: SocialSnapshot) -> some View {
        VStack(spacing: 14) {
            HStack {
                SectionHeading(title: "В объективе", subtitle: "Личные фотографии из ОК")
                NavigationLink("Все") { PhotosView() }.modifier(GlassActionStyle())
            }
            if data.photos.isEmpty {
                Text(data.issues.contains { $0.section == "photos" } ? "Раздел пока недоступен" : "Личный альбом пока пуст")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(data.photos.prefix(4)) { photo in
                        Button { selectedPhoto = photo } label: { PhotoTile(photo: photo, height: 180) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
