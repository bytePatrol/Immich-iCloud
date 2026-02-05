import SwiftUI
import Photos

struct SelectiveSyncView: View {
    @Environment(AppState.self) private var appState
    @State private var assets: [PHAsset] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoading = false
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var searchText = ""
    @State private var showOnlySelected = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)
    ]

    private var filteredAssets: [PHAsset] {
        var result = assets
        if showOnlySelected {
            result = result.filter { selectedIds.contains($0.localIdentifier) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding()
                .background(.bar)

            Divider()

            // Asset grid
            if isLoading {
                ProgressView("Loading assets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty {
                emptyState
            } else {
                assetGrid
            }
        }
        .task {
            await loadAssets()
            await loadSelectedIds()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Selective Sync")
                .font(.headline)

            Spacer()

            Toggle("Show Selected Only", isOn: $showOnlySelected)
                .toggleStyle(.checkbox)
                .help("Filter to show only assets you've selected for sync")

            Divider()
                .frame(height: 20)

            Text("\(selectedIds.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Number of assets currently selected for selective sync")

            Button("Select All Visible") {
                selectAllVisible()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add all currently visible assets to your selection")

            Button("Clear Selection") {
                clearSelection()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedIds.isEmpty)
            .help("Remove all assets from your selection")

            Button {
                Task { await loadAssets() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh asset list")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Assets Found")
                .font(.headline)
            Text("Scan your Photos library to see assets here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Scan Library") {
                Task { await loadAssets() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Asset Grid

    private var assetGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(filteredAssets, id: \.localIdentifier) { asset in
                    AssetThumbnailCell(
                        asset: asset,
                        thumbnail: thumbnails[asset.localIdentifier],
                        isSelected: selectedIds.contains(asset.localIdentifier),
                        onToggle: { toggleSelection(asset) },
                        onLoadThumbnail: { await loadThumbnail(for: asset) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ asset: PHAsset) {
        let id = asset.localIdentifier
        Task {
            do {
                if selectedIds.contains(id) {
                    selectedIds.remove(id)
                    try await LedgerStore.shared.removeFromSelection(localAssetId: id)
                } else {
                    selectedIds.insert(id)
                    try await LedgerStore.shared.addToSelection(localAssetId: id)
                }
                await appState.refreshSelectionCount()
            } catch {
                AppLogger.shared.error("Failed to update selection: \(error.localizedDescription)", category: "UI")
            }
        }
    }

    private func selectAllVisible() {
        let visibleIds = filteredAssets.map { $0.localIdentifier }
        Task {
            do {
                try await LedgerStore.shared.addToSelection(localAssetIds: visibleIds)
                selectedIds.formUnion(visibleIds)
                await appState.refreshSelectionCount()
            } catch {
                AppLogger.shared.error("Failed to select all: \(error.localizedDescription)", category: "UI")
            }
        }
    }

    private func clearSelection() {
        Task {
            do {
                try await LedgerStore.shared.clearSelection()
                selectedIds.removeAll()
                await appState.refreshSelectionCount()
            } catch {
                AppLogger.shared.error("Failed to clear selection: \(error.localizedDescription)", category: "UI")
            }
        }
    }

    // MARK: - Data Loading

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }

        let result = await PhotoLibraryService.shared.fetchAssets(
            after: appState.config.startDate,
            filterConfig: appState.config.filterConfig
        )
        assets = result.assets
    }

    private func loadSelectedIds() async {
        do {
            selectedIds = try await LedgerStore.shared.getSelectedAssetIds()
        } catch {
            AppLogger.shared.error("Failed to load selected IDs: \(error.localizedDescription)", category: "UI")
        }
    }

    private func loadThumbnail(for asset: PHAsset) async {
        guard thumbnails[asset.localIdentifier] == nil else { return }
        if let thumbnail = await PhotoLibraryService.shared.requestThumbnail(for: asset, size: CGSize(width: 120, height: 120)) {
            thumbnails[asset.localIdentifier] = thumbnail
        }
    }
}

// MARK: - Asset Thumbnail Cell

private struct AssetThumbnailCell: View {
    let asset: PHAsset
    let thumbnail: NSImage?
    let isSelected: Bool
    let onToggle: () -> Void
    let onLoadThumbnail: () async -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.tertiary)
                            .overlay {
                                Image(systemName: asset.mediaType == .video ? "video" : "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 100, height: 100)
                .clipped()
                .cornerRadius(8)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .white)
                    .shadow(radius: 2)
                    .padding(4)

                // Video duration badge
                if asset.mediaType == .video {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                        Text(formatDuration(asset.duration))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? .blue : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .task {
            await onLoadThumbnail()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration / 60)
        let secs = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }
}
