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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.availableAlbums.isEmpty {
                Button("Load Albums") {
                    Task {
                        let result = await PhotoLibraryService.shared.fetchAlbums()
                        appState.availableAlbums = result.userAlbums + result.smartAlbums
                    }
                }
                .buttonStyle(.bordered)
                .help("Fetch user albums and smart albums from your Photos library")
            } else {
                let ids = selectedIds
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.availableAlbums) { album in
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
                                        Text(album.title)
                                            .font(.body)
                                        Text("\(album.assetCount) assets\(album.isSmartAlbum ? " (Smart Album)" : "")")
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
                }
                .frame(maxHeight: 200)
            }
        }
    }
}
