import SwiftUI
import SwiftData

struct ConnectAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var applicationKey = OKConfiguration.applicationKey
    @State private var accessToken = ""
    @State private var sessionSecret = ""
    @State private var oauth = OKOAuthSession()
    @State private var authenticating = false
    @State private var authError: String?
    var isSheet = false

    private var busy: Bool { authenticating || store.isConnecting }
    private var canConnect: Bool {
        !applicationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !accessToken.isEmpty && !sessionSecret.isEmpty
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image("AppMark").resizable().frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    Text("Ваш ОК.\nНа вашем iPhone.").font(.largeTitle.bold())
                    Text("Войдите, чтобы увидеть свой профиль, друзей и фотографии в нативном интерфейсе.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.clear)

            Section {
                Button(action: signIn) {
                    HStack {
                        Spacer()
                        if busy { ProgressView() }
                        Label("Войти через ОК", systemImage: "person.crop.circle.badge.checkmark").fontWeight(.semibold)
                        Spacer()
                    }.padding(.vertical, 10)
                }
                .modifier(GlassActionStyle(prominent: true))
                .accessibilityIdentifier("connection.oauth")
                Text("Вход откроется в защищённом системном окне. Пароль остаётся на стороне ОК.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message = authError ?? store.connectionError {
                    Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red)
                }
            }.listRowBackground(Color.clear)

            Section {
                DisclosureGroup("Личные токены разработчика") {
                    TextField("Публичный ключ приложения", text: $applicationKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connection.applicationKey")
                    SecureField("access_token", text: $accessToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connection.accessToken")
                    SecureField("session_secret_key", text: $sessionSecret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connection.sessionSecret")
                    Text("Запасной способ для владельца приложения: создайте пару токенов в настройках ОК. Секретный ключ самого приложения сюда вводить не нужно.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Подключить по токенам", action: connectTokens)
                        .modifier(GlassActionStyle()).disabled(!canConnect)
                        .accessibilityIdentifier("connection.submit")
                }
            } footer: {
                Text("Токены проверяются запросом к ОК и сохраняются только в Keychain этого iPhone.")
            }

            Section {
                Link("Настройка доступа и разрешений", destination: URL(string: "https://apiok.ru/dev/app/create")!)
            }
        }
        .navigationTitle("Подключение ОК").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .toolbar {
            if isSheet { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .onDisappear {
            accessToken = ""; sessionSecret = ""
            if !authenticating { oauth.cancel() }
        }
    }

    private func signIn() {
        authenticating = true
        authError = nil
        store.connectionError = nil
        Task {
            defer { authenticating = false }
            do {
                let tokens = try await oauth.authenticate()
                let success = await store.connect(applicationKey: tokens.applicationKey ?? OKConfiguration.applicationKey,
                    token: tokens.accessToken, secret: tokens.sessionSecretKey ?? "", expiresAt: tokens.expiresAt, context: context)
                if success { dismiss() }
            } catch is CancellationError { }
            catch { authError = (error as? OKOAuthFlow.Failure)?.localizedDescription ?? "Не удалось завершить вход в ОК." }
        }
    }

    private func connectTokens() {
        authError = nil
        Task {
            let success = await store.connect(applicationKey: applicationKey, token: accessToken,
                                              secret: sessionSecret, context: context)
            if success { accessToken = ""; sessionSecret = ""; dismiss() }
        }
    }
}
