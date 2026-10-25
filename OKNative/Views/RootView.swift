import SwiftUI
import SwiftData

enum AppTab: Hashable { case feed, profile, photos, settings }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .profile
    @State private var reconnect = false

    var body: some View {
        Group {
          if store.sessionState == .restoring { ProgressView("Открываем ОК…") }
          else if store.sessionState == .signedOut {
            NavigationStack { ConnectAccountView() }
          } else {
           VStack(spacing: 0) {
            if store.sessionState == .expired {
                Button { reconnect = true } label: {
                    Label("Сессия истекла · Подключить снова", systemImage: "key")
                        .font(.subheadline).frame(maxWidth: .infinity).padding(10)
                }.modifier(GlassActionStyle())
            }
            TabView(selection: $selection) {
            NavigationStack { FeedView() }
                .tabItem { Label("Лента", systemImage: "rectangle.stack") }.tag(AppTab.feed)
            NavigationStack { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }.tag(AppTab.profile)
            NavigationStack { PhotosView() }
                .tabItem { Label("Фото", systemImage: "photo.on.rectangle.angled") }.tag(AppTab.photos)
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }.tag(AppTab.settings)
            }.modifier(LiquidTabBehavior())
           }
          }
        }
        .task { await store.restore(context: context) }
        .sheet(isPresented: $reconnect) { NavigationStack { ConnectAccountView(isSheet: true) } }
        .alert("Не удалось выполнить действие", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct LoadingContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context

    var body: some View {
        if store.isLoading {
            ProgressView("Загружаем моменты…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Пока нет данных", systemImage: "tray")
            } description: {
                Text("Обновите данные профиля. При отсутствии интернета ранее сохранённые данные будут доступны из кеша.")
            } actions: {
                Button("Попробовать снова") { Task { await store.load(context: context, refresh: true) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

