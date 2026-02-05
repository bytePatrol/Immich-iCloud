import Foundation

actor ImmichClient {
    private var baseURL: String
    private var apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
    }

    func updateCredentials(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // MARK: - Connection Test

    func testConnection() async throws -> ImmichServerInfo {
        // Ping (public endpoint — verifies server is reachable)
        let pingURL = try buildURL(path: "/api/server/ping")
        let pingData = try await performGET(url: pingURL)
        let ping = try decoder.decode(ImmichPingResponse.self, from: pingData)
        guard ping.res == "pong" else {
            throw AppError.immichConnectionFailed("Unexpected ping response: \(ping.res)")
        }

        // Version (public endpoint)
        let versionURL = try buildURL(path: "/api/server/version")
        let versionData = try await performGET(url: versionURL)
        let version = try decoder.decode(ImmichServerVersion.self, from: versionData)

        // Validate API key (authenticated endpoint)
        let myUserURL = try buildURL(path: "/api/users/me")
        _ = try await performGET(url: myUserURL)

        return ImmichServerInfo(
            version: version.displayString,
            isAvailable: true
        )
    }

    // MARK: - Asset Upload

    func uploadAsset(
        data: Data,
        fileName: String,
        creationDate: Date?,
        mediaType: MediaType
    ) async throws -> ImmichUploadResponse {
        let url = try buildURL(path: "/api/assets")
        let boundary = "Immich-iCloud-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        var body = Data()

        // Device asset ID field
        appendFormField(to: &body, boundary: boundary, name: "deviceAssetId", value: fileName)

        // Device ID
        appendFormField(to: &body, boundary: boundary, name: "deviceId", value: "Immich-iCloud-macOS")

        // File creation date
        if let date = creationDate {
            let dateStr = Self.iso8601Formatter.string(from: date)
            appendFormField(to: &body, boundary: boundary, name: "fileCreatedAt", value: dateStr)
            appendFormField(to: &body, boundary: boundary, name: "fileModifiedAt", value: dateStr)
        } else {
            let now = Self.iso8601Formatter.string(from: Date())
            appendFormField(to: &body, boundary: boundary, name: "fileCreatedAt", value: now)
            appendFormField(to: &body, boundary: boundary, name: "fileModifiedAt", value: now)
        }

        // MIME type
        let mimeType = mimeTypeForFile(fileName: fileName, mediaType: mediaType)

        // File data
        appendFileField(to: &body, boundary: boundary, name: "assetData", fileName: fileName, mimeType: mimeType, data: data)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: responseData)

        return try decoder.decode(ImmichUploadResponse.self, from: responseData)
    }

    // MARK: - Asset Info (for diffing)

    func getAssetInfo(id: String) async throws -> ImmichAssetInfo {
        let url = try buildURL(path: "/api/assets/\(id)")
        let data = try await performGET(url: url)
        return try decoder.decode(ImmichAssetInfo.self, from: data)
    }

    // MARK: - Albums (F9: Album Creation on Immich)

    func createAlbum(name: String, description: String? = nil) async throws -> ImmichAlbumResponse {
        let url = try buildURL(path: "/api/albums")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        struct CreateAlbumRequest: Codable {
            let albumName: String
            let description: String?
        }

        let reqBody = CreateAlbumRequest(albumName: name, description: description)
        request.httpBody = try JSONEncoder().encode(reqBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        return try decoder.decode(ImmichAlbumResponse.self, from: data)
    }

    func addAssetsToAlbum(albumId: String, assetIds: [String]) async throws {
        guard !assetIds.isEmpty else { return }

        let url = try buildURL(path: "/api/albums/\(albumId)/assets")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        struct AddAssetsRequest: Codable {
            let ids: [String]
        }

        let reqBody = AddAssetsRequest(ids: assetIds)
        request.httpBody = try JSONEncoder().encode(reqBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    func listAlbums() async throws -> [ImmichAlbumInfo] {
        let url = try buildURL(path: "/api/albums")
        let data = try await performGET(url: url)
        return try decoder.decode([ImmichAlbumInfo].self, from: data)
    }

    func getAlbum(id: String) async throws -> ImmichAlbumInfo {
        let url = try buildURL(path: "/api/albums/\(id)")
        let data = try await performGET(url: url)
        return try decoder.decode(ImmichAlbumInfo.self, from: data)
    }

    // MARK: - Asset Search (F7: Two-Way Sync)

    func searchAssets(page: Int = 1, pageSize: Int = 1000) async throws -> ImmichAssetSearchResult {
        let url = try buildURL(path: "/api/search/metadata")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        struct SearchRequest: Codable {
            let page: Int
            let size: Int
            let deviceId: String?
        }

        // Filter by our device ID to only get assets we uploaded
        let reqBody = SearchRequest(page: page, size: pageSize, deviceId: "Immich-iCloud-macOS")
        request.httpBody = try JSONEncoder().encode(reqBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let searchResponse = try decoder.decode(ImmichSearchResponse.self, from: data)
        return searchResponse.assets
    }

    func getAllOurAssets() async throws -> [ImmichAssetSummary] {
        var allAssets: [ImmichAssetSummary] = []
        var page = 1
        let pageSize = 1000

        while true {
            let result = try await searchAssets(page: page, pageSize: pageSize)
            allAssets.append(contentsOf: result.items)

            if result.items.count < pageSize || result.nextPage == nil {
                break
            }
            page += 1
        }

        return allAssets
    }

    func deleteAssets(ids: [String], force: Bool = false) async throws {
        guard !ids.isEmpty else { return }

        let url = try buildURL(path: "/api/assets")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        struct DeleteRequest: Codable {
            let ids: [String]
            let force: Bool
        }

        let reqBody = DeleteRequest(ids: ids, force: force)
        request.httpBody = try JSONEncoder().encode(reqBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    // MARK: - Check for Existing Asset by Checksum

    func checkExistingAssets(checksums: [String]) async throws -> [String: String] {
        let url = try buildURL(path: "/api/assets/bulk-upload-check")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        struct BulkCheckRequest: Codable {
            let assets: [AssetCheck]
            struct AssetCheck: Codable {
                let id: String
                let checksum: String
            }
        }
        struct BulkCheckResponse: Codable {
            let results: [CheckResult]
            struct CheckResult: Codable {
                let id: String
                let assetId: String?
                let action: String  // "accept" or "reject"
            }
        }

        let reqBody = BulkCheckRequest(
            assets: checksums.enumerated().map { idx, checksum in
                BulkCheckRequest.AssetCheck(id: "\(idx)", checksum: checksum)
            }
        )
        request.httpBody = try JSONEncoder().encode(reqBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let result = try decoder.decode(BulkCheckResponse.self, from: data)

        var mapping: [String: String] = [:]
        for item in result.results {
            if let assetId = item.assetId {
                let idx = Int(item.id) ?? 0
                if idx < checksums.count {
                    mapping[checksums[idx]] = assetId
                }
            }
        }
        return mapping
    }

    // MARK: - Private Helpers

    private func buildURL(path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: trimmed + path) else {
            throw AppError.immichConnectionFailed("Invalid server URL: \(baseURL)")
        }
        return url
    }

    private func applyAuth(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Immich-iCloud/1.0", forHTTPHeaderField: "User-Agent")
    }

    private func performGET(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.immichConnectionFailed("Invalid response type")
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to parse structured error from Immich
            if let errorResponse = try? decoder.decode(ImmichErrorResponse.self, from: data) {
                throw AppError.immichConnectionFailed("HTTP \(http.statusCode): \(errorResponse.displayMessage)")
            }
            // Fallback: show raw body for debugging
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "Non-UTF8 response"
            throw AppError.immichConnectionFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    // MARK: - Multipart Helpers

    private func appendFormField(to body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileField(to body: inout Data, boundary: String, name: String, fileName: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func mimeTypeForFile(fileName: String, mediaType: MediaType) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "tiff", "tif": return "image/tiff"
        case "raw", "dng", "cr2", "nef", "arw": return "image/raw"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "avi": return "video/avi"
        default:
            return mediaType == .video ? "video/mp4" : "image/jpeg"
        }
    }
}
