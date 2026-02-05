import Foundation

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var minimumOS: String {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "14.0"
    }

    static var fullVersion: String {
        "\(marketing) (\(build))"
    }

    static var sparkleURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }
}
