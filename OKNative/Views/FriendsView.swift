import SwiftUI

struct FriendsView: View {
    let friends: [DemoFriend]
    @State private var search = ""

    private var filtered: [DemoFriend] {
        friends.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(filtered) { friend in
            NavigationLink { FriendDetailView(friend: friend) } label: {
                HStack(spacing: 14) {
                    Avatar(asset: friend.avatar, size: 54, online: friend.isOnline)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(friend.name).font(.headline)
                        Text(friend.isOnline ? "В сети · \(friend.detail)" : friend.detail)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }
        }
        .searchable(text: $search, prompt: "Найти друга")
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Друзья")
    }
}

struct FriendDetailView: View {
    let friend: DemoFriend

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Avatar(asset: friend.avatar, size: 112, online: friend.isOnline).padding(.top, 32)
                Text(friend.name).font(.title2.bold()).multilineTextAlignment(.center)
                Label(friend.detail, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                if friend.isOnline { Text("В сети").font(.subheadline).foregroundStyle(.green) }
                ContentUnavailableView("Вы уже друзья", systemImage: "person.2.fill",
                    description: Text("Это демонстрационный профиль. Сообщения и реальные данные появятся после подключения API Одноклассников."))
            }.padding(20)
        }
        .background(OKTheme.background).navigationTitle("Профиль друга").navigationBarTitleDisplayMode(.inline)
    }
}

