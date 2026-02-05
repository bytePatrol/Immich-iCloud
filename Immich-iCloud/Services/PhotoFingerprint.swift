import Foundation
import CryptoKit

struct PhotoFingerprint {
    static func generate(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func generate(fromFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return generate(from: data)
    }
}
