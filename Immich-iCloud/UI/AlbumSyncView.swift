import SwiftUI

struct AlbumSyncView: View {
    @Environment(AppState.self) private var appState
    @State private var localAlbums: [AlbumInfo] = []
    @State private var albumMappings: [AlbumMapping] = []
    @State private var immichAlbums: [ImmichAlbumInfo] = []
    @State private var isLoading = false
    @State private var isSyncing = false
    @State private var syncingAlbumId: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()
                .background(.bar)

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading albums...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = errorMessage {
                            errorBanner(error)
                        }

                        if !albumMappings.isEmpty {
                            mappedAlbumsSection
                        }

                        availableAlbumsSection
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Album Sync")
                    .font(.headline)
                Text("Create and sync albums on your Immich server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
            .help("Reload album mappings and Immich albums")
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Mapped Albums Section

    private var mappedAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synced Albums")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(albumMappings, id: \.id) { mapping in
                MappedAlbumRow(
                    mapping: mapping,
                    isSyncing: syncingAlbumId == mapping.localAlbumId,
                    onSync: { await syncAlbum(mapping) }
                )
            }
        }
    }

    // MARK: - Available Albums Section

    private var availableAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Albums")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Load Albums") {
                    Task { await loadLocalAlbums() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
                .help("Fetch available albums from your Photos library")
            }

            if localAlbums.isEmpty {
                Text("Click 'Load Albums' to see available albums from your Photos library.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                let unmappedAlbums = localAlbums.filter { album in
                    !albumMappings.contains { $0.localAlbumId == album.id }
                }

                if unmappedAlbums.isEmpty {
                    Text("All albums are already mapped.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(unmappedAlbums) { album in
                        AvailableAlbumRow(
                            album: album,
                            onAdd: { await addAlbumMapping(album) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            albumMappings = try await LedgerStore.shared.getAllAlbumMappings()

            if appState.hasValidCredentials {
                let engine = AlbumSyncEngine(baseURL: appState.serverURL, apiKey: appState.apiKey)
                immichAlbums = try await engine.listImmichAlbums()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLocalAlbums() async {
        let result = await PhotoLibraryService.shared.fetchAlbums()
        localAlbums = result.userAlbums + result.smartAlbums + result.sharedAlbums
    }

    private func addAlbumMapping(_ album: AlbumInfo) async {
        guard appState.hasValidCredentials else {
            errorMessage = "Configure Immich server credentials first"
            return
        }

        do {
            let engine = AlbumSyncEngine(baseURL: appState.serverURL, apiKey: appState.apiKey)
            let mapping = try await engine.createAlbumMapping(for: album)
            albumMappings.append(mapping)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncAlbum(_ mapping: AlbumMapping) async {
        guard appState.hasValidCredentials else {
            errorMessage = "Configure Immich server credentials first"
            return
        }

        syncingAlbumId = mapping.localAlbumId
        defer { syncingAlbumId = nil }

        do {
            let engine = AlbumSyncEngine(baseURL: appState.serverURL, apiKey: appState.apiKey)
            let updated = try await engine.syncAlbum(mapping: mapping)

            if let idx = albumMappings.firstIndex(where: { $0.id == updated.id }) {
                albumMappings[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Mapped Album Row

private struct MappedAlbumRow: View {
    let mapping: AlbumMapping
    let isSyncing: Bool
    let onSync: () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.localAlbumTitle)
                    .font(.body)
                HStack(spacing: 8) {
                    if let immichId = mapping.immichAlbumId {
                        Label("Immich: \(immichId.prefix(8))...", systemImage: "link")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Text("\(mapping.assetCount) assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastSync = mapping.lastSyncedAt {
                        Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Sync") {
                    Task { await onSync() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Sync new assets from this album to Immich")
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Available Album Row

private struct AvailableAlbumRow: View {
    let album: AlbumInfo
    let onAdd: () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(album.title)
                        .font(.body)
                    if album.isSharedAlbum {
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("This is a shared album from iCloud")
                    }
                    if album.isSmartAlbum {
                        Text("Smart")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .cornerRadius(4)
                            .help("Smart albums are dynamically populated by Photos based on criteria")
                    }
                }
                Text("\(album.assetCount) assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Add to Immich") {
                Task { await onAdd() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Create this album on Immich and sync its assets")
        }
        .padding()
        .background(.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
