import Foundation
import Photos
import AppKit

actor PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    private init() {}

    // MARK: - Authorization

    func requestAccess() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status
    }

    nonisolated func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Asset Enumeration

    struct FetchResult {
        let assets: [PHAsset]
        let totalInLibrary: Int
        let filteredOut: Int
    }

    func fetchAssets(after startDate: Date?, filterConfig: FilterConfig = FilterConfig()) async -> FetchResult {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false

        // Build compound predicate from filters
        var predicates: [NSPredicate] = []

        // Start Date filter
        if let startDate {
            predicates.append(NSPredicate(format: "creationDate >= %@", startDate as NSDate))
        }

        // Media type filter
        switch filterConfig.mediaTypeFilter {
        case .photosOnly:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case .videosOnly:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        case .all:
            break
        }

        // Favorites filter
        if filterConfig.favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }

        if !predicates.isEmpty {
            fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        var assets: [PHAsset] = []

        // Album-based fetching
        switch filterConfig.albumFilterMode {
        case .all:
            let allResult = PHAsset.fetchAssets(with: fetchOptions)
            assets.reserveCapacity(allResult.count)
            allResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

        case .selectedOnly:
            // Only include assets from selected albums
            var seenIds = Set<String>()
            for albumId in filterConfig.selectedAlbumIds {
                let collections = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumId], options: nil
                )
                guard let collection = collections.firstObject else { continue }
                let albumAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                albumAssets.enumerateObjects { asset, _, _ in
                    if seenIds.insert(asset.localIdentifier).inserted {
                        assets.append(asset)
                    }
                }
            }

        case .excludeSelected:
            // Fetch all, then exclude assets in excluded albums
            let allResult = PHAsset.fetchAssets(with: fetchOptions)
            var excludedIds = Set<String>()
            for albumId in filterConfig.excludedAlbumIds {
                let collections = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumId], options: nil
                )
                guard let collection = collections.firstObject else { continue }
                let albumAssets = PHAsset.fetchAssets(in: collection, options: nil)
                albumAssets.enumerateObjects { asset, _, _ in
                    excludedIds.insert(asset.localIdentifier)
                }
            }
            assets.reserveCapacity(allResult.count)
            allResult.enumerateObjects { asset, _, _ in
                if !excludedIds.contains(asset.localIdentifier) {
                    assets.append(asset)
                }
            }
        }

        // Count total for stats
        let totalOptions = PHFetchOptions()
        totalOptions.includeHiddenAssets = false
        let totalCount = PHAsset.fetchAssets(with: totalOptions).count
        let filteredOut = totalCount - assets.count

        return FetchResult(
            assets: assets,
            totalInLibrary: totalCount,
            filteredOut: filteredOut
        )
    }

    // MARK: - Album Enumeration

    struct AlbumFetchResult {
        let userAlbums: [AlbumInfo]
        let smartAlbums: [AlbumInfo]
    }

    func fetchAlbums() -> AlbumFetchResult {
        var userAlbums: [AlbumInfo] = []
        var smartAlbums: [AlbumInfo] = []

        // User albums
        let userCollections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userCollections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            userAlbums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                assetCount: count,
                isSmartAlbum: false
            ))
        }

        // Smart albums (Favorites, Screenshots, etc.)
        let smartCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .any, options: nil
        )
        smartCollections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            smartAlbums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                assetCount: count,
                isSmartAlbum: true
            ))
        }

        return AlbumFetchResult(
            userAlbums: userAlbums.sorted { $0.title < $1.title },
            smartAlbums: smartAlbums.sorted { $0.title < $1.title }
        )
    }

    // MARK: - Asset Resource Info

    struct AssetResourceInfo {
        let filename: String
        let fileSize: Int64
        let uniformTypeIdentifier: String?
    }

    func resourceInfo(for asset: PHAsset) -> AssetResourceInfo? {
        let resources = PHAssetResource.assetResources(for: asset)
        // Prefer the primary resource (original photo/video)
        let primary = resources.first { resource in
            resource.type == .photo || resource.type == .video
        } ?? resources.first

        guard let resource = primary else { return nil }

        let size = resource.value(forKey: "fileSize") as? Int64 ?? 0
        return AssetResourceInfo(
            filename: resource.originalFilename,
            fileSize: size,
            uniformTypeIdentifier: resource.uniformTypeIdentifier
        )
    }

    // MARK: - Thumbnail Generation

    func requestThumbnail(for asset: PHAsset, size: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Full Asset Data (for upload/fingerprinting)

    struct MaterializedAsset {
        let data: Data
        let filename: String
        let uniformTypeIdentifier: String?
    }

    func requestImageData(for asset: PHAsset) async throws -> MaterializedAsset? {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false

            imageManager.requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, uti, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                let resources = PHAssetResource.assetResources(for: asset)
                let filename = resources.first?.originalFilename ?? "unknown"
                continuation.resume(returning: MaterializedAsset(
                    data: data,
                    filename: filename,
                    uniformTypeIdentifier: uti
                ))
            }
        }
    }

    func requestVideoData(for asset: PHAsset) async throws -> MaterializedAsset? {
        // Export video to a temporary file, then read the data
        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .video }) ?? resources.first else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(videoResource.originalFilename.components(separatedBy: ".").last ?? "mov")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(
                for: videoResource,
                toFile: tempURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try Data(contentsOf: tempURL)
        return MaterializedAsset(
            data: data,
            filename: videoResource.originalFilename,
            uniformTypeIdentifier: videoResource.uniformTypeIdentifier
        )
    }

    // MARK: - Cache Management

    func startCaching(assets: [PHAsset], size: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assets: [PHAsset], size: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: nil)
    }

    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }
}
