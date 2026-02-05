import SwiftUI
import Photos

struct PreviewView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var filterType: MediaTypeFilter = .all
    @State private var selectedAssetId: String?

    private var filteredAssets: [AssetSummary] {
        appState.scannedAssets.filter { asset in
            if filterType == .photos && asset.mediaType != .photo { return false }
            if filterType == .videos && asset.mediaType != .video { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return asset.filename.lowercased().contains(q) ||
                       asset.localAssetId.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if appState.photosAuthorization == .denied || appState.photosAuthorization == .restricted {
                permissionDeniedView
            } else if appState.scannedAssets.isEmpty && !appState.isScanning {
                emptyView
            } else {
                assetListView
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Asset Preview")
                .font(.largeTitle.bold())
            Spacer()

            if !appState.scannedAssets.isEmpty {
                Picker("Type", selection: $filterType) {
                    Text("All").tag(MediaTypeFilter.all)
                    Text("Photos").tag(MediaTypeFilter.photos)
                    Text("Videos").tag(MediaTypeFilter.videos)
                }
                .frame(width: 100)
                .help("Filter the asset list by media type")

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .help("Search by filename or local asset ID")
            }

            Button {
                Task { await appState.scanPhotosLibrary() }
            } label: {
                if appState.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Scan Library", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.isScanning)
            .help("Enumerate assets from your Photos library using current filter settings")
        }
        .padding(24)
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            EmptyStateView(
                icon: "photo.badge.exclamationmark",
                title: "Photos Access Required",
                message: "Immich-iCloud needs access to your Photos library. Grant access in System Settings > Privacy & Security > Photos."
            )
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            if appState.photosAuthorization == .notDetermined {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "Photos Access Needed",
                    message: "Click 'Scan Library' to request Photos access and scan your library."
                )
            } else {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No Assets Scanned",
                    message: "Click 'Scan Library' to enumerate assets from your Photos library."
                )
            }
            Spacer()
        }
    }

    // MARK: - Asset List

    private var assetListView: some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 16) {
                Label("\(appState.totalInLibrary) total in library", systemImage: "photo.stack")
                    .help("Total assets in your Photos library before any filters")
                if appState.filteredOutCount > 0 {
                    Label("\(appState.filteredOutCount) before Start Date", systemImage: "calendar.badge.minus")
                        .help("Assets excluded because they were created before the Start Date filter")
                }
                Label("\(filteredAssets.count) shown", systemImage: "eye")
                    .help("Assets currently visible after applying search and type filters")
                Spacer()

                if appState.isScanning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            Divider()

            // Asset list with detail
            HSplitView {
                List(filteredAssets, selection: $selectedAssetId) { asset in
                    AssetRow(asset: asset)
                        .tag(asset.id)
                        .task {
                            await appState.loadThumbnail(for: asset.id)
                        }
                }
                .listStyle(.plain)
                .frame(minWidth: 350)

                // Detail panel
                if let selectedId = selectedAssetId,
                   let asset = appState.scannedAssets.first(where: { $0.id == selectedId }) {
                    assetDetailPanel(asset)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text("Select an asset to view details")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(minWidth: 280)
                }
            }
        }
    }

    // MARK: - Asset Detail

    private func assetDetailPanel(_ asset: AssetSummary) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Large thumbnail
                Group {
                    if let thumb = asset.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: asset.mediaType == .video ? "video.fill" : "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                StatusPill(status: asset.status)

                // File Info
                GroupBox("File Info") {
                    VStack(alignment: .leading, spacing: 6) {
                        metadataRow("Filename", value: asset.filename)
                        metadataRow("Type", value: asset.mediaType.rawValue.capitalized)
                        if let size = asset.formattedFileSize {
                            metadataRow("Size", value: size)
                        }
                        if let res = asset.resolution {
                            metadataRow("Resolution", value: res)
                        }
                        if let dur = asset.formattedDuration {
                            metadataRow("Duration", value: dur)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Dates
                GroupBox("Dates") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = asset.creationDate {
                            metadataRow("Created", value: date.formatted(date: .long, time: .shortened))
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Identifiers
                GroupBox("Identifiers") {
                    VStack(alignment: .leading, spacing: 6) {
                        metadataRow("Local ID", value: asset.localAssetId)
                        if let fp = asset.fingerprint {
                            metadataRow("Fingerprint", value: String(fp.prefix(16)) + "...")
                        }
                        if let immichId = asset.immichAssetId {
                            metadataRow("Immich ID", value: immichId)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Filter

private enum MediaTypeFilter {
    case all, photos, videos
}
