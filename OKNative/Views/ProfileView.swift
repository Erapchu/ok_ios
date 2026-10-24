import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage("profile.name") private var customName = ""
    @AppStorage("profile.bio") private var customBio = ""
    @AppStorage("profile.edited") private var profileEdited = false
    @State private var editing = false
    @State private var selectedPhoto: DemoPhoto?

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                ScrollView {
                    VStack(spacing: 24) {
                        profileCard(snapshot)
                        friendsCard(snapshot)
                        photosSection(snapshot)
                        aboutCard(snapshot)
                        Label("Тестовый профиль · данные доступны офлайн", systemImage: "checkmark.seal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
                .refreshable { await store.load(context: context, refresh: true) }
            } else { LoadingContent() }
        }
        .background(OKTheme.background)
        .navigationTitle("Мой профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Text("ок").font(.title2.bold()).foregroundStyle(OKTheme.orange).accessibilityLabel("ОК, нативный клиент") }
            ToolbarItem(placement: .topBarTrailing) { DemoLabel() }
        }
        .sheet(isPresented: $editing) {
            if let profile = store.snapshot?.profile {
                EditProfileView(name: profileEdited ? customName : profile.name,
                                bio: profileEdited ? customBio : profile.bio) { name, bio in
                    customName = name
                    customBio = bio
                    profileEdited = true
                }
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(photos: store.snapshot?.photos ?? [photo], initialID: photo.id)
        }
    }

    private func profileCard(_ snapshot: SocialSnapshot) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Image("photo-lake").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
                .frame(height: 146)
                .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topTrailing) {
                    Label("Мои моменты", systemImage: "sun.max")
                        .font(.caption.weight(.medium)).foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.2), in: Capsule()).padding(14)
                }
            VStack(spacing: 12) {
                Avatar(asset: snapshot.profile.avatar, size: 100, online: true).padding(.top, -50)
                Text(profileEdited ? customName : snapshot.profile.name)
                    .font(.title2.bold()).multilineTextAlignment(.center)
                Label(snapshot.profile.city, systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(profileEdited ? customBio : snapshot.profile.bio)
                    .font(.subheadline).multilineTextAlignment(.center).lineSpacing(3)
                    .padding(.horizontal, 12)
                Button { editing = true } label: {
                    Label("Редактировать профиль", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 0) {
                    NavigationLink { FriendsView(friends: snapshot.friends) } label: {
                        statistic("\(snapshot.friends.count)", title: "друга")
                    }
                    Divider().frame(height: 30)
                    NavigationLink { PhotosView() } label: { statistic("\(snapshot.photos.count)", title: "фотографий") }
                    Divider().frame(height: 30)
                    NavigationLink { FeedView(onlyOwnPosts: true) } label: {
                        statistic("\(snapshot.posts.filter { $0.avatar == snapshot.profile.avatar }.count)", title: "публикация")
                    }
                }
                .buttonStyle(.plain).padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(OKTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.top, 10)
    }

    private func statistic(_ value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(.primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    private func friendsCard(_ snapshot: SocialSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Люди рядом", subtitle: "Друзья, с которыми на одной волне")
                NavigationLink { FriendsView(friends: snapshot.friends) } label: {
                    Image(systemName: "arrow.up.right").font(.body.weight(.semibold)).padding(10)
                }.accessibilityLabel("Все друзья")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(snapshot.friends) { friend in
                        NavigationLink { FriendDetailView(friend: friend) } label: {
                            VStack(spacing: 8) {
                                Avatar(asset: friend.avatar, size: 58, online: friend.isOnline)
                                Text(friend.name.components(separatedBy: " ").first ?? friend.name)
                                    .font(.caption).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(3)
            }
        }
    }

    private func photosSection(_ snapshot: SocialSnapshot) -> some View {
        VStack(spacing: 14) {
            HStack {
                SectionHeading(title: "В объективе", subtitle: "Маленькие истории из моей жизни")
                NavigationLink("Все") { PhotosView() }.font(.subheadline.weight(.semibold))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(snapshot.photos.prefix(4)) { photo in
                    Button { selectedPhoto = photo } label: { PhotoTile(photo: photo, height: 175) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func aboutCard(_ snapshot: SocialSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Немного обо мне").font(.headline)
            Label(snapshot.profile.city, systemImage: "house")
            Label("Путешествия, фотография, хорошая музыка", systemImage: "heart")
            Label("Открыт новым впечатлениям", systemImage: "sparkles")
        }
        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).background(OKTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var bio: String
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") { TextField("Как вас зовут", text: $name).textContentType(.name) }
                Section("О себе") { TextField("Что вам нравится", text: $bio, axis: .vertical).lineLimit(3...6) }
                Section { Text("Изменения сохраняются только на этом iPhone в демо-профиле.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Редактирование").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), bio.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
