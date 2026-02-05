import Foundation

// MARK: - Server Info

struct ImmichPingResponse: Codable {
    let res: String  // "pong"
}

struct ImmichServerVersion: Codable {
    let major: Int
    let minor: Int
    let patch: Int

    var displayString: String {
        "v\(major).\(minor).\(patch)"
    }
}

struct ImmichServerInfo {
    let version: String
    let isAvailable: Bool
}

// MARK: - Upload

struct ImmichUploadResponse: Codable {
    let id: String
    let status: String?
    let duplicate: Bool?

    var isDuplicate: Bool {
        duplicate == true || status == "duplicate"
    }
}

// MARK: - Asset Info (for diffing)

struct ImmichAssetInfo: Codable {
    let id: String
    let originalFileName: String?
    let originalPath: String?
    let fileCreatedAt: String?
    let fileModifiedAt: String?
    let type: String?
    let checksum: String?

    // Exif sub-object
    let exifInfo: ImmichExifInfo?
}

struct ImmichExifInfo: Codable {
    let make: String?
    let model: String?
    let exifImageWidth: Int?
    let exifImageHeight: Int?
    let fileSizeInByte: Int64?
    let orientation: String?
    let dateTimeOriginal: String?
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Error Response

struct ImmichErrorResponse: Codable {
    let message: ImmichErrorMessage?
    let error: String?
    let statusCode: Int?

    var displayMessage: String {
        let msg: String
        switch message {
        case .single(let s): msg = s
        case .array(let arr): msg = arr.joined(separator: "; ")
        case .none: msg = error ?? "Unknown error"
        }
        return msg
    }
}

/// Immich returns `message` as either a string or an array of strings
enum ImmichErrorMessage: Codable {
    case single(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .single(str)
        } else if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else {
            self = .single("Unknown error")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        }
    }
}

// MARK: - Albums (F9: Album Creation on Immich)

struct ImmichAlbumResponse: Codable {
    let id: String
    let albumName: String
    let description: String?
    let createdAt: String
    let updatedAt: String
    let assetCount: Int?
}

struct ImmichAlbumInfo: Codable, Identifiable {
    let id: String
    let albumName: String
    let description: String?
    let createdAt: String
    let updatedAt: String
    let assetCount: Int?
    let ownerId: String?
}

struct ImmichAddAssetsResponse: Codable {
    let id: String
    let success: Bool?
    let error: String?
}

struct ImmichBulkAddAssetsResponse: Codable {
    let successfullyAdded: Int?
    let alreadyInAlbum: [String]?
}

// MARK: - Asset Search (F7: Two-Way Sync)

struct ImmichAssetSummary: Codable, Identifiable {
    let id: String
    let deviceId: String?
    let deviceAssetId: String?
    let checksum: String?
    let originalFileName: String?
    let fileCreatedAt: String?
    let type: String?
}

struct ImmichSearchResponse: Codable {
    let assets: ImmichAssetSearchResult
}

struct ImmichAssetSearchResult: Codable {
    let items: [ImmichAssetSummary]
    let total: Int
    let count: Int
    let nextPage: String?
}

struct ImmichDeleteResponse: Codable {
    // No content expected on success (204)
}
