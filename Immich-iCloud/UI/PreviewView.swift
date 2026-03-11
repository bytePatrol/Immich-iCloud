import SwiftUI
import Photos
import AVKit
import AVFoundation

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
                    AssetDetailView(asset: asset)
                        .environment(appState)
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
}

// MARK: - Asset Detail View

struct AssetDetailView: View {
    @Environment(AppState.self) private var appState
    let asset: AssetSummary

    @State private var player: AVPlayer?
    @State private var isLoadingVideo = false
    @State private var showNeverUploadConfirm = false
    @State private var showForceReUploadConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Media display (video player or thumbnail)
                mediaView
                    .frame(height: asset.mediaType == .video ? 300 : nil)
                    .frame(maxHeight: asset.mediaType == .video ? 300 : 250)
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
                        metadataRow("Immich ID", value: asset.immichAssetId ?? "—")
                    }
                    .padding(.vertical, 4)
                }

                // Actions
                GroupBox("Actions") {
                    VStack(spacing: 8) {
                        Button(role: .destructive) {
                            showNeverUploadConfirm = true
                        } label: {
                            Label("Never Upload", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(asset.status == .ignored)
                        .help("Mark this asset to be permanently skipped during sync")

                        Button {
                            showForceReUploadConfirm = true
                        } label: {
                            Label("Force Re-Upload Now", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isSyncing)
                        .help(appState.isSyncing ? "Cannot re-upload while a sync is in progress" : "Reset this asset and upload it to Immich immediately")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280)
        .task(id: asset.id) {
            // Load video player when a video asset is selected
            player?.pause()
            player = nil
            guard asset.mediaType == .video else { return }

            isLoadingVideo = true
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localAssetId], options: nil)
            if let phAsset = fetchResult.firstObject,
               let avAsset = await PhotoLibraryService.shared.requestAVAsset(for: phAsset) {
                let item = AVPlayerItem(asset: avAsset)
                player = AVPlayer(playerItem: item)
            }
            isLoadingVideo = false
        }
        .onDisappear {
            player?.pause()
        }
        .confirmationDialog(
            "Never Upload \"\(asset.filename)\"?",
            isPresented: $showNeverUploadConfirm,
            titleVisibility: .visible
        ) {
            Button("Never Upload", role: .destructive) {
                Task { await appState.markNeverUpload(localAssetId: asset.localAssetId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This asset will be skipped during all future syncs. You can undo this by resetting the ledger.")
        }
        .confirmationDialog(
            "Force Re-Upload \"\(asset.filename)\"?",
            isPresented: $showForceReUploadConfirm,
            titleVisibility: .visible
        ) {
            Button("Re-Upload Now") {
                Task { await appState.forceReUpload(localAssetId: asset.localAssetId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The upload record will be reset and this asset will be uploaded to Immich immediately.")
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        if asset.mediaType == .video {
            if let player {
                AVPlayerViewRepresentable(player: player)
            } else if isLoadingVideo {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        } else {
            if let thumb = asset.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
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

// MARK: - AVPlayerView wrapper (avoids _AVKit_SwiftUI crash on macOS 26)

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

// MARK: - Filter

private enum MediaTypeFilter {
    case all, photos, videos
}
