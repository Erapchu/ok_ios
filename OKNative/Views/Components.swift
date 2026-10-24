import SwiftUI

enum OKTheme {
    static let orange = Color(red: 0.94, green: 0.40, blue: 0.10)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct Avatar: View {
    let asset: String
    var size: CGFloat = 48
    var online = false

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.background, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                if online {
                    Circle().fill(.green)
                        .frame(width: max(12, size * 0.18), height: max(12, size * 0.18))
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
    }
}

struct DemoLabel: View {
    var body: some View {
        Label("ДЕМО", systemImage: "sparkle")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(OKTheme.orange)
            .background(OKTheme.orange.opacity(0.1), in: Capsule())
            .accessibilityLabel("Демонстрационный режим")
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PhotoTile: View {
    let photo: DemoPhoto
    var height: CGFloat = 150
    var showTitle = true

    var body: some View {
        GeometryReader { geometry in
            Image(photo.asset)
                .resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .bottomLeading) {
                    if showTitle {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photo.title).font(.subheadline.bold())
                            Text(photo.location).font(.caption)
                        }
                        .foregroundStyle(.white).padding(12)
                    }
                }
                .clipped()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(photo.title), \(photo.location)")
    }
}

