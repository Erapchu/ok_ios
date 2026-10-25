import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true
    @State private var confirmingClear = false
    @State private var cacheCleared = false
    @State private var connecting = false
    @State private var confirmingSignOut = false

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
                LabeledContent("Источник данных", value: store.isPreview ? "Демо для проверки интерфейса" : "API Одноклассников")
                if let date = store.updatedAt {
                    LabeledContent("Кеш обновлён") { Text(date, format: .dateTime.day().month().hour().minute()).foregroundStyle(.secondary) }
                } else { LabeledContent("Кеш", value: "Пуст") }
                Button {
                    Task { await store.load(context: context, refresh: true) }
                } label: {
                    HStack {
                        Label("Обновить данные", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.isLoading { ProgressView() }
                    }
                }.disabled(store.isLoading)
                Button(role: .destructive) { confirmingClear = true } label: {
                    Label("Очистить кеш", systemImage: "trash")
                }.disabled(store.isLoading || store.updatedAt == nil)
            } header: { Text("Данные на устройстве") } footer: {
                Text("Профиль и ранее открытые фотографии доступны из локального кеша. Избранное сохраняется только на этом iPhone и не отправляется в ОК.")
            }
            Section {
                if store.isPreview {
                    Label("Предпросмотр интерфейса", systemImage: "sparkles")
                } else {
                    Label(store.snapshot?.profile.name ?? "Аккаунт ОК", systemImage: "person.crop.circle")
                    Button("Обновить доступ") { connecting = true }
                    Button("Выйти из аккаунта", role: .destructive) { confirmingSignOut = true }
                    Text("Токены защищены Keychain. При выходе токены, кеш и локальное избранное удаляются с этого iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Аккаунт") }
            Section("О приложении") {
                LabeledContent("Версия", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                NavigationLink("О прототипе") { AboutView() }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить локальный кеш?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Очистить кеш", role: .destructive) {
                Task {
                    await store.clearCache(context: context)
                    cacheCleared = store.updatedAt == nil
                }
            }
        } message: { Text("Избранное и настройки сохранятся. Для повторной загрузки фотографий потребуется интернет.") }
        .alert("Кеш очищен", isPresented: $cacheCleared) {
            Button("Готово", role: .cancel) { }
        } message: { Text("Открытые данные остаются в памяти до закрытия приложения.") }
        .sheet(isPresented: $connecting) { NavigationStack { ConnectAccountView(isSheet: true) } }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Выйти и удалить данные", role: .destructive) { Task { await store.signOut(context: context) } }
        } message: { Text("Токены, кеш и локальное избранное будут удалены с этого iPhone.") }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section("ОК на iPhone") {
                Text("Неофициальный нативный клиент Одноклассников. Профиль, друзья и личные фотографии загружаются из API вашего аккаунта.")
                Text("Интерфейс построен на SwiftUI. Локальный кеш — SwiftData. Сетевой слой использует URLSession и Swift Concurrency.")
                Text("На iOS 26 используется Liquid Glass. На iOS 17–18 приложение использует стандартное оформление этих версий системы.")
            }
            Section("Следующий шаг") {
                Text("В этой версии поддерживается личный доступ владельца приложения по паре токенов разработчика. Вход через OAuth, лента, публикации и изменение профиля пока не подключены.")
            }
            Section("Фотографии") {
                Text("В режиме API показываются ваши фотографии. Ресурсы Unsplash используются только для отладки интерфейса и тестов.")
            }
        }.navigationTitle("О прототипе").navigationBarTitleDisplayMode(.inline)
    }
}
