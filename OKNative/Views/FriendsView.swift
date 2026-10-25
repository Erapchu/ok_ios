import SwiftUI
import SwiftData

struct FriendsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var search = ""

    private var filtered: [SocialFriend] {
        (store.snapshot?.friends ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(filtered) { friend in
                NavigationLink { FriendDetailView(friend: friend) } label: {
                    HStack(spacing: 14) {
                        Avatar(asset: friend.avatar, size: 54, online: friend.isOnline)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(friend.name).font(.headline)
                            if friend.isOnline { Text("В сети").font(.caption).foregroundStyle(.green) }
                            if !friend.detail.isEmpty { Text(friend.detail).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 5)
                }
            }
            if let data = store.snapshot, data.hasMoreFriends {
                Section {
                    Button {
                        Task { await store.loadMoreFriends(context: context) }
                    } label: {
                        HStack {
                            Text("Загрузить ещё друзей")
                            Spacer()
                            if store.isLoadingMore { ProgressView() }
                        }
                    }.disabled(store.isLoadingMore)
                } footer: {
                    Text("Загружено \(data.friends.count) из \(data.totalFriends). Поиск выполняется среди загруженных друзей.")
                }
            }
        }
        .searchable(text: $search, prompt: "Найти друга")
        .overlay {
            if filtered.isEmpty && store.snapshot?.hasMoreFriends != true {
                if search.isEmpty {
                    ContentUnavailableView("Друзья", systemImage: "person.2",
                        description: Text(store.snapshot?.issues.first { $0.section == "friends" }?.message
                            ?? ((store.snapshot?.totalFriends ?? 0) > 0 ? "ОК не вернул доступные профили. Попробуйте обновить данные." : "Список друзей пока пуст.")))
                } else { ContentUnavailableView.search(text: search) }
            }
        }
        .navigationTitle("Друзья")
    }
}

struct FriendDetailView: View {
    let friend: SocialFriend
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Avatar(asset: friend.avatar, size: 112, online: friend.isOnline).padding(.top, 32)
                Text(friend.name).font(.title2.bold()).multilineTextAlignment(.center)
                if !friend.detail.isEmpty { Label(friend.detail, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                if friend.isOnline { Text("В сети").font(.subheadline).foregroundStyle(.green) }
                if let url = URL(string: "https://ok.ru/profile/\(friend.id)"), !friend.id.contains(where: { !$0.isNumber }) {
                    Link("Открыть профиль в ОК", destination: url).modifier(GlassActionStyle(prominent: true))
                }
            }.padding(24).frame(maxWidth: .infinity)
        }
        .background(OKTheme.background).navigationTitle("Профиль друга").navigationBarTitleDisplayMode(.inline)
    }
}
