import SwiftUI
import SwiftData

struct PhotosView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var filter = "Все"
    @State private var selectedPhoto: SocialPhoto?
    private var filters: [String] { ["Все", "Избранное"] }

    private var photos: [SocialPhoto] {
        (store.snapshot?.photos ?? []).filter {
            filter == "Все" || (filter == "Избранное" ? store.isSaved("photo:\($0.id)") : $0.album == filter)
        }
    }

    var body: some View {
        Group {
            if store.snapshot == nil { LoadingContent() } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeading(title: "Жизнь в кадре", subtitle: "Места, к которым хочется вернуться")
                        if let issue = store.snapshot?.issues.first(where: { $0.section == "photos" }) {
                            Text(issue.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filters, id: \.self) { item in
                                    Button { filter = item } label: {
                                        Text(item).font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .foregroundStyle(filter == item ? .white : .primary)
                                    }.modifier(GlassActionStyle(prominent: filter == item))
                                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                                }
                            }
                        }
                        if photos.isEmpty {
                            ContentUnavailableView("Пока пусто", systemImage: "heart",
                                description: Text(filter == "Избранное" ? "Откройте фотографию и нажмите на сердечко. Избранное хранится на этом iPhone." : "В личном альбоме пока нет доступных фотографий."))
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(photos) { photo in
                                    Button { selectedPhoto = photo } label: {
                                        PhotoTile(photo: photo, height: 215)
                                            .overlay(alignment: .topTrailing) {
                                                if store.isSaved("photo:\(photo.id)") {
                                                    Image(systemName: "heart.fill").font(.caption.bold())
                                                        .foregroundStyle(.white).padding(8)
                                                        .background(OKTheme.orange, in: Circle()).padding(10)
                                                }
                                            }
                                    }.buttonStyle(.plain)
                                }
                            }
                            Text("\(photos.count) фото · \(store.isPreview ? "демо-альбом" : "личный альбом ОК")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if store.snapshot?.photoAnchor != nil {
                            Button {
                                Task { await store.loadMorePhotos(context: context) }
                            } label: {
                                HStack { Text("Загрузить ещё"); if store.isLoadingMore { ProgressView() } }
                            }.modifier(GlassActionStyle()).disabled(store.isLoadingMore)
                        }
                    }.padding(20)
                }
                .refreshable { await store.load(context: context, refresh: true) }
            }
        }
        .background(OKTheme.background)
        .navigationTitle("Фотографии")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoLabel() } }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(photos: photos, initialID: photo.id)
        }
    }
}

struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppStore.self) private var store
    @AppStorage("haptics") private var haptics = true
    @State private var photos: [SocialPhoto]
    @State private var selection: String

    init(photos: [SocialPhoto], initialID: String) {
        _photos = State(initialValue: photos)
        _selection = State(initialValue: initialID)
    }

    private var current: SocialPhoto? { photos.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                }.modifier(GlassActionStyle()).accessibilityLabel("Закрыть фотографию")
                Spacer()
                if let index = photos.firstIndex(where: { $0.id == selection }) {
                    Text("\(index + 1) / \(photos.count)").font(.subheadline.monospacedDigit())
                }
            }.padding(.horizontal, 20).padding(.top, 12)
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    MediaImage(reference: photo.asset, mode: .fit).padding(.vertical, 20)
                        .tag(photo.id).accessibilityLabel("\(photo.title), \(photo.location)")
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            if let photo = current {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(photo.title).font(.title3.bold())
                        if !photo.location.isEmpty {
                            Label(photo.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        store.toggle("photo:\(photo.id)", context: context)
                    } label: {
                        Image(systemName: store.isSaved("photo:\(photo.id)") ? "heart.fill" : "heart")
                            .font(.title2).foregroundStyle(store.isSaved("photo:\(photo.id)") ? OKTheme.orange : .white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(store.isSaved("photo:\(photo.id)") ? "Убрать из избранного" : "В избранное")
                    .sensoryFeedback(.selection, trigger: store.isSaved("photo:\(photo.id)")) { _, _ in haptics }
                    if let url = URL(string: photo.asset), url.scheme == "https" {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").font(.title2).frame(width: 44, height: 44)
                        }.accessibilityLabel("Поделиться ссылкой на фотографию")
                    } else {
                        ShareLink(item: Image(photo.asset), preview: SharePreview(photo.title, image: Image(photo.asset))) {
                            Image(systemName: "square.and.arrow.up").font(.title2).frame(width: 44, height: 44)
                        }.accessibilityLabel("Поделиться фотографией")
                    }
                }.padding(20).modifier(FloatingGlass()).padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

