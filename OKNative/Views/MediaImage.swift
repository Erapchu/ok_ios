import SwiftUI

struct MediaImage: View {
    let reference: String
    var mode: ContentMode = .fill
    @State private var loaded: UIImage?
    @State private var failed = false

    private var remoteURL: URL? {
        guard let url = URL(string: reference), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let url = remoteURL {
                if let loaded { Image(uiImage: loaded).resizable().aspectRatio(contentMode: mode) }
                else {
                    placeholder.overlay { if !failed { ProgressView() } }
                }
            } else if !reference.isEmpty, !reference.contains("://") {
                Image(reference).resizable().aspectRatio(contentMode: mode)
            } else { placeholder }
        }
        .task(id: reference) {
            loaded = nil
            failed = false
            guard let url = remoteURL else { return }
            do {
                let data = try await MediaCache.shared.data(for: url)
                try Task.checkCancellation()
                loaded = UIImage(data: data)
                failed = loaded == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(.secondary.opacity(0.12))
            .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
    }
}

struct GlassActionStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

struct FloatingGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: .rect(cornerRadius: 24)) }
        else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)) }
    }
}

struct LiquidTabBehavior: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.tabBarMinimizeBehavior(.never) }
        else { content }
    }
}
