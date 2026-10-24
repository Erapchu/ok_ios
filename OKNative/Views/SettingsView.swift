import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true
    @State private var confirmingClear = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("AppMark").resizable().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ОК · нативный клиент").font(.headline)
                        Text("Ближе к людям. Ближе к iPhone.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("Интерфейс") {
                Picker(selection: $appearance) {
                    Text("Как на iPhone").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                } label: { Label("Оформление", systemImage: "circle.lefthalf.filled") }
                Toggle(isOn: $haptics) { Label("Тактильный отклик", systemImage: "hand.tap") }
            }
            Section {
                LabeledContent("Источник данных", value: "Демонстрационный")
                if let date = store.updatedAt {
                    LabeledContent("Кеш обновлён") { Text(date, format: .dateTime.day().month().hour().minute()).foregroundStyle(.secondary) }
                } else { LabeledContent("Кеш", value: "Пуст") }
                Button {
                    Task { await store.load(context: context, refresh: true) }
                } label: {
                    HStack {
                        Label("Обновить демо-данные", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.isLoading { ProgressView() }
                    }
                }.disabled(store.isLoading)
                Button(role: .destructive) { confirmingClear = true } label: {
                    Label("Очистить кеш", systemImage: "trash")
                }.disabled(store.isLoading || store.updatedAt == nil)
            } header: { Text("Данные на устройстве") } footer: {
                Text("Профиль и фотографии работают без интернета. Избранное, классы и изменения профиля сохраняются отдельно от кеша.")
            }
            Section {
                Label("Авторизация пока не подключена", systemImage: "lock.shield")
                Text("Сейчас приложение не запрашивает пароль или токен ОК. Для следующего этапа подготовлено хранилище Keychain.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Аккаунт") }
            Section("О приложении") {
                LabeledContent("Версия", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                NavigationLink("О прототипе") { AboutView() }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить локальный кеш?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Очистить кеш", role: .destructive) {
                store.clearCache(context: context)
                cacheCleared = store.updatedAt == nil
            }
        } message: { Text("Избранное и настройки сохранятся. Демо-данные можно загрузить заново.") }
        .alert("Кеш очищен", isPresented: $cacheCleared) {
            Button("Готово", role: .cancel) { }
        } message: { Text("Открытые данные остаются в памяти до закрытия приложения.") }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section("Первый шаг") {
                Text("Неофициальный нативный прототип клиента Одноклассников. Все имена, профили, статусы и публикации — демонстрационные.")
                Text("Интерфейс построен на SwiftUI. Локальный кеш — SwiftData. Сетевой слой использует URLSession и Swift Concurrency.")
            }
            Section("Следующий шаг") {
                Text("Регистрация приложения в ОК, проверка доступных разрешений API и подключение OAuth. Набор функций будет зависеть от доступа, который предоставляет платформа.")
            }
            Section("Фотографии") {
                Text("Демонстрационные фотографии: Unsplash. Источники изображений приведены в ASSET_CREDITS.md в репозитории.")
            }
        }.navigationTitle("О прототипе").navigationBarTitleDisplayMode(.inline)
    }
}
