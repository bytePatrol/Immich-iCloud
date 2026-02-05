import Foundation
import AppKit

enum AssetStatus: String, Codable, CaseIterable {
    case new = "new"
    case uploaded = "uploaded"
    case blocked = "blocked"
    case ignored = "ignored"
    case failed = "failed"
}

enum MediaType: String, Codable {
    case photo
    case video
    case unknown
}

struct AssetSummary: Identifiable {
    let id: String
    let localAssetId: String
    let filename: String
    let creationDate: Date?
    let mediaType: MediaType
    let fileSize: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let duration: Double?
    var status: AssetStatus
    var fingerprint: String?
    var immichAssetId: String?
    var thumbnail: NSImage?

    var resolution: String? {
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return nil }
        return "\(w) x \(h)"
    }

    var formattedDuration: String? {
        guard let d = duration, d > 0 else { return nil }
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedFileSize: String? {
        guard let size = fileSize, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
