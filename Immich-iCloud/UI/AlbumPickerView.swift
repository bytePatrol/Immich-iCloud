import SwiftUI

struct AlbumPickerView: View {
    @Environment(AppState.self) private var appState
    let mode: FilterConfig.AlbumFilterMode

    private var selectedIds: Binding<[String]> {
        @Bindable var appState = appState
        return mode == .selectedOnly
            ? $appState.config.filterConfig.selectedAlbumIds
            : $appState.config.filterConfig.excludedAlbumIds
    }

    private var userAlbums: [AlbumInfo] {
        appState.availableAlbums.filter { !$0.isSmartAlbum && !$0.isSharedAlbum }
    }

    private var smartAlbums: [AlbumInfo] {
        appState.availableAlbums.filter { $0.isSmartAlbum }
    }

    private var sharedAlbums: [AlbumInfo] {
        appState.availableAlbums.filter { $0.isSharedAlbum }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.availableAlbums.isEmpty {
                Button("Load Albums") {
                    Task {
                        let result = await PhotoLibraryService.shared.fetchAlbums()
                        appState.availableAlbums = result.userAlbums + result.smartAlbums + result.sharedAlbums
                    }
                }
                .buttonStyle(.bordered)
                .help("Fetch user albums, smart albums, and shared albums from your Photos library")
            } else {
                let ids = selectedIds
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !userAlbums.isEmpty {
                            albumSection(title: "My Albums", albums: userAlbums, ids: ids)
                        }

                        if !sharedAlbums.isEmpty {
                            albumSection(title: "Shared Albums", albums: sharedAlbums, ids: ids)
                        }

                        if !smartAlbums.isEmpty {
                            albumSection(title: "Smart Albums", albums: smartAlbums, ids: ids)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    @ViewBuilder
    private func albumSection(title: String, albums: [AlbumInfo], ids: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(albums) { album in
                albumRow(album: album, ids: ids)
            }
        }
    }

    @ViewBuilder
    private func albumRow(album: AlbumInfo, ids: Binding<[String]>) -> some View {
        let isSelected = ids.wrappedValue.contains(album.id)
        Button {
            if isSelected {
                ids.wrappedValue.removeAll { $0 == album.id }
            } else {
                ids.wrappedValue.append(album.id)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(album.title)
                            .font(.body)
                        if album.isSharedAlbum {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(album.assetCount) assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
