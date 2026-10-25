import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    var onlyOwnPosts = false
    @State private var selectedPhoto: SocialPhoto?

    var body: some View {
        Group {
            if !store.isPreview {
                ContentUnavailableView {
                    Label("Лента пока недоступна", systemImage: "rectangle.stack")
                } description: {
                    Text("Для этой версии подключены профиль, друзья и фотографии. Доступ к ленте требует отдельной проверки возможностей API вашего приложения.")
                } actions: {
                    Link("Открыть ленту в ОК", destination: URL(string: "https://ok.ru")!)
                        .modifier(GlassActionStyle(prominent: true))
                }
            } else if let snapshot = store.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !onlyOwnPosts {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Хорошо быть рядом").font(.title2.bold())
                                    Text("Новости и моменты ваших друзей").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(OKTheme.orange)
                            }.padding(.horizontal, 4)
                        }
                        ForEach(snapshot.posts.filter { !onlyOwnPosts || $0.avatar == snapshot.profile.avatar }) { post in
                            FeedPostCard(post: post, photo: snapshot.photos.first { $0.id == post.photoID }) { photo in
                                selectedPhoto = photo
                            }
                        }
                        Text("Вы посмотрели все демонстрационные публикации")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    }.padding(20)
                }
                .refreshable { await store.load(context: context, refresh: true) }
            } else { LoadingContent() }
        }
        .background(OKTheme.background)
        .navigationTitle(onlyOwnPosts ? "Мои публикации" : "Лента")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoLabel() } }
        .fullScreenCover(item: $selectedPhoto) { photo in PhotoViewer(photos: [photo], initialID: photo.id) }
    }
}

private struct FeedPostCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage("haptics") private var haptics = true
    @AppStorage("profile.name") private var customName = ""
    let post: FeedPost
    let photo: SocialPhoto?
    let openPhoto: (SocialPhoto) -> Void
    private var liked: Bool { store.isSaved("post:\(post.id)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Avatar(asset: post.avatar)
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.avatar == "avatar-alex" && !customName.isEmpty ? customName : post.author).font(.subheadline.bold())
                    Text(post.date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "leaf").foregroundStyle(OKTheme.orange).accessibilityHidden(true)
            }
            Text(post.text).font(.body).lineSpacing(4)
            if let photo {
                Button { openPhoto(photo) } label: { PhotoTile(photo: photo, height: 240, showTitle: false) }
                    .buttonStyle(.plain)
            }
            HStack {
                Button { store.toggle("post:\(post.id)", context: context) } label: {
                    Label("Класс! · \(post.likes + (liked ? 1 : 0))", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(liked ? OKTheme.orange.opacity(0.12) : OKTheme.background, in: Capsule())
                }
                .accessibilityLabel(liked ? "Убрать класс, \(post.likes + 1) отметок" : "Поставить класс, \(post.likes) отметок")
                .sensoryFeedback(.selection, trigger: liked) { _, _ in haptics }
                Spacer()
                ShareLink(item: post.text) {
                    Image(systemName: "square.and.arrow.up").font(.body).frame(width: 44, height: 44)
                }.accessibilityLabel("Поделиться текстом публикации")
            }
        }
        .padding(18).background(OKTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

