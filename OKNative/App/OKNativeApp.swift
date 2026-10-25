import SwiftUI
import SwiftData

@main
struct OKNativeApp: App {
    @AppStorage("appearance") private var appearance = "system"
    @State private var store: AppStore
    private let container: ModelContainer?

    init() {
        #if DEBUG
        _store = State(initialValue: ProcessInfo.processInfo.arguments.contains("--preview-demo")
                       ? AppStore(service: DemoSocialService()) : AppStore())
        #else
        _store = State(initialValue: AppStore())
        #endif
        // Keep a recoverable error screen if the disk store cannot be opened.
        container = try? ModelContainer(for: CachedSnapshot.self, SavedReaction.self)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .environment(store)
                        .modelContainer(container)
                } else {
                    ContentUnavailableView("Не удалось открыть хранилище",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Перезапустите приложение и проверьте свободное место на iPhone."))
                }
            }
            .tint(OKTheme.orange)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
    }
}

