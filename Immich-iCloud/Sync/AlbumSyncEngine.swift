import Foundation
import Photos

actor AlbumSyncEngine {
    private let client: ImmichClient

    init(baseURL: String, apiKey: String) {
        self.client = ImmichClient(baseURL: baseURL, apiKey: apiKey)
    }

    // MARK: - Create Album Mapping

    func createAlbumMapping(for album: AlbumInfo) async throws -> AlbumMapping {
        // Check if mapping already exists
        if let existing = try await LedgerStore.shared.getAlbumMapping(localAlbumId: album.id) {
            return existing
        }

        // Create local mapping (Immich album will be created on first sync)
        return try await LedgerStore.shared.createAlbumMapping(
            localAlbumId: album.id,
            localAlbumTitle: album.title
        )
    }

    // MARK: - Sync Album to Immich

    func syncAlbum(mapping: AlbumMapping) async throws -> AlbumMapping {
        var updated = mapping

        // Step 1: Create Immich album if needed
        if updated.immichAlbumId == nil {
            let immichAlbum = try await client.createAlbum(
                name: updated.localAlbumTitle,
                description: "Synced from iCloud Photos via Immich-iCloud"
            )
            updated.immichAlbumId = immichAlbum.id
            try await LedgerStore.shared.updateAlbumMapping(updated)
            let albumTitle = updated.localAlbumTitle
            let albumId = immichAlbum.id
            Task { @MainActor in
                AppLogger.shared.info("Created Immich album '\(albumTitle)' (\(albumId))", category: "Album")
            }
        }

        guard let immichAlbumId = updated.immichAlbumId else {
            throw AppError.albumSyncFailed("Failed to create Immich album")
        }

        // Step 2: Fetch assets from local album
        let localAssetIds = await fetchLocalAlbumAssetIds(localAlbumId: updated.localAlbumId)

        // Step 3: Add asset links to database
        for localAssetId in localAssetIds {
            guard let mappingId = updated.id else { continue }
            try await LedgerStore.shared.addAlbumAssetLink(albumMappingId: mappingId, localAssetId: localAssetId)
        }

        // Step 4: Get unsynced assets that have been uploaded to Immich
        guard let mappingId = updated.id else {
            throw AppError.albumSyncFailed("Album mapping has no ID")
        }

        let unsyncedLinks = try await LedgerStore.shared.getUnSyncedAlbumAssetLinks(albumMappingId: mappingId)

        // Step 5: Find Immich asset IDs for our local assets
        var immichAssetIds: [String] = []
        var syncedLocalIds: [String] = []

        for link in unsyncedLinks {
            // Look up the Immich asset ID from our ledger
            if let ledgerRecord = try await LedgerStore.shared.record(forLocalAssetId: link.localAssetId),
               ledgerRecord.status == AssetStatus.uploaded.rawValue,
               let immichAssetId = ledgerRecord.immichAssetId {
                immichAssetIds.append(immichAssetId)
                syncedLocalIds.append(link.localAssetId)
            }
        }

        // Step 6: Add assets to Immich album
        if !immichAssetIds.isEmpty {
            try await client.addAssetsToAlbum(albumId: immichAlbumId, assetIds: immichAssetIds)

            // Mark links as synced
            try await LedgerStore.shared.markAlbumAssetLinksAsSynced(
                albumMappingId: mappingId,
                localAssetIds: syncedLocalIds
            )

            let count = immichAssetIds.count
            let albumTitle = updated.localAlbumTitle
            Task { @MainActor in
                AppLogger.shared.info("Added \(count) assets to album '\(albumTitle)'", category: "Album")
            }
        }

        // Step 7: Update mapping stats
        updated.lastSyncedAt = Date()
        updated.assetCount = try await LedgerStore.shared.getAlbumAssetCount(albumMappingId: mappingId)
        try await LedgerStore.shared.updateAlbumMapping(updated)

        return updated
    }

    // MARK: - List Immich Albums

    func listImmichAlbums() async throws -> [ImmichAlbumInfo] {
        try await client.listAlbums()
    }

    // MARK: - Helpers

    private func fetchLocalAlbumAssetIds(localAlbumId: String) async -> [String] {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [localAlbumId],
            options: nil
        )
        guard let collection = collections.firstObject else { return [] }

        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        var ids: [String] = []
        ids.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }

        return ids
    }
}
