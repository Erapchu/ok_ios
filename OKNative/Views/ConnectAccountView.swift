import SwiftUI
import SwiftData

struct ConnectAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var applicationKey = ""
    @State private var accessToken = ""
    @State private var sessionSecret = ""
    var isSheet = false

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
                    Text("Подключите аккаунт, чтобы увидеть свой профиль, друзей и фотографии в нативном интерфейсе.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.clear)
            Section {
                TextField("Публичный ключ приложения", text: $applicationKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("connection.applicationKey")
                SecureField("access_token", text: $accessToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("connection.accessToken")
                SecureField("session_secret_key", text: $sessionSecret)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("connection.sessionSecret")
            } header: { Text("Личный доступ разработчика") } footer: {
                Text("Это пара токенов вашего аккаунта из настроек приложения ОК. Она сохраняется в Keychain только после успешной проверки. Секретный ключ самого приложения сюда вводить не нужно.")
            }
            if let message = store.connectionError {
                Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task {
                        let success = await store.connect(applicationKey: applicationKey, token: accessToken,
                                                          secret: sessionSecret, context: context)
                        if success {
                            accessToken = ""; sessionSecret = ""
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if store.isConnecting { ProgressView() }
                        Text(store.isConnecting ? "Проверяем доступ…" : "Подключить аккаунт").fontWeight(.semibold)
                        Spacer()
                    }.padding(.vertical, 8)
                }
                .modifier(GlassActionStyle(prominent: true))
                .disabled(!canConnect || store.isConnecting)
                .accessibilityIdentifier("connection.submit")
            }.listRowBackground(Color.clear)
            Section("Как получить доступ") {
                Text("1. Зарегистрируйте приложение в ОК и добавьте платформу OAuth.")
                Text("2. Запросите разрешение VALUABLE_ACCESS, если оно ещё не выдано.")
                Text("3. В настройках приложения создайте пару access_token и session_secret_key для своего аккаунта. После изменения разрешений создайте новую пару.")
                Link("Открыть инструкцию ОК", destination: URL(string: "https://apiok.ru/dev/app/create")!)
                Text("Этот способ предназначен для личного клиента владельца приложения. Обычный вход через OAuth будет отдельным этапом после регистрации и настройки приложения.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Подключение ОК").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .disabled(store.isConnecting)
        .interactiveDismissDisabled(store.isConnecting)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
        .onDisappear { accessToken = ""; sessionSecret = "" }
    }
}
