import Foundation
import AppKit

@MainActor
final class AppLogger {
    static let shared = AppLogger()

    private static let maxEvents = 10_000

    private(set) var events: [LogEvent] = []
    var onNewEvent: ((LogEvent) -> Void)?

    private init() {}

    // MARK: - Logging

    func log(_ message: String, level: LogEvent.LogLevel = .info, category: String = "General") {
        let event = LogEvent(
            timestamp: Date(),
            level: level,
            message: message,
            category: category
        )
        events.append(event)

        // Rotate if over max
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }

        onNewEvent?(event)
    }

    func debug(_ message: String, category: String = "General") {
        log(message, level: .debug, category: category)
    }

    func info(_ message: String, category: String = "General") {
        log(message, level: .info, category: category)
    }

    func warning(_ message: String, category: String = "General") {
        log(message, level: .warning, category: category)
    }

    func error(_ message: String, category: String = "General") {
        log(message, level: .error, category: category)
    }

    func clear() {
        events.removeAll()
    }

    // MARK: - Export

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func exportText() -> String {
        events.map { event in
            let ts = Self.timestampFormatter.string(from: event.timestamp)
            return "[\(ts)] [\(event.level.rawValue)] [\(event.category)] \(event.message)"
        }.joined(separator: "\n")
    }

    func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Immich-iCloud-logs-\(Self.fileTimestamp()).txt"
        panel.title = "Export Logs"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = exportText()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            info("Logs exported to \(url.lastPathComponent)", category: "Logger")
        } catch {
            self.error("Failed to export logs: \(error.localizedDescription)", category: "Logger")
        }
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
