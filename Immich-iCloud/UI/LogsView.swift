import SwiftUI

struct LogsView: View {
    @Environment(AppState.self) private var appState

    @State private var filterLevel: LogEvent.LogLevel? = nil
    @State private var searchText: String = ""

    private var filteredEvents: [LogEvent] {
        appState.logEvents.filter { event in
            if let level = filterLevel, event.level != level {
                return false
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return event.message.lowercased().contains(query) ||
                       event.category.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Logs")
                    .font(.largeTitle.bold())
                Spacer()

                // Filter by level
                Picker("Level", selection: $filterLevel) {
                    Text("All").tag(LogEvent.LogLevel?.none)
                    ForEach([LogEvent.LogLevel.debug, .info, .warning, .error], id: \.rawValue) { level in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForLevel(level))
                                .frame(width: 6, height: 6)
                            Text(level.rawValue.capitalized)
                        }
                        .tag(LogEvent.LogLevel?.some(level))
                    }
                }
                .frame(width: 120)
                .help("Filter log events by severity level")

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .help("Search log messages and categories")

                Button {
                    AppLogger.shared.exportToFile()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(appState.logEvents.isEmpty)
                .help("Save all log events to a text file for sharing or debugging")

                Button {
                    appState.logEvents.removeAll()
                    AppLogger.shared.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(appState.logEvents.isEmpty)
                .help("Remove all log events from the current session")
            }
            .padding(24)

            Divider()

            if filteredEvents.isEmpty {
                Spacer()
                if appState.logEvents.isEmpty {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "No Log Events",
                        message: "Log events from sync operations will appear here."
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Matching Logs",
                        message: "Try adjusting your filter or search query."
                    )
                }
                Spacer()
            } else {
                List(filteredEvents) { event in
                    HStack(spacing: 8) {
                        Image(systemName: iconForLevel(event.level))
                            .font(.caption)
                            .foregroundStyle(colorForLevel(event.level))
                            .frame(width: 14)

                        Text(event.level.rawValue.prefix(4).uppercased())
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(colorForLevel(event.level))
                            .frame(width: 36, alignment: .leading)

                        Text(event.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                            .lineLimit(1)

                        Text(event.message)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer()

                        Text(event.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)

                // Footer with count
                HStack {
                    Text("\(filteredEvents.count) of \(appState.logEvents.count) events")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let lastEvent = filteredEvents.last {
                        Text("Latest: \(lastEvent.timestamp.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }
        }
    }

    private func colorForLevel(_ level: LogEvent.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func iconForLevel(_ level: LogEvent.LogLevel) -> String {
        switch level {
        case .debug: return "ant"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}
