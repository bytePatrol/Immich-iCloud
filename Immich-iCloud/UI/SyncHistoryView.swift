import SwiftUI

struct SyncHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = HistoryTab.sessions
    @State private var sessions: [SyncSession] = []
    @State private var summary: SyncSessionSummary?
    @State private var ledgerRecords: [LedgerRecord] = []
    @State private var filterStatus: AssetStatus?
    @State private var isLoading = true
    @State private var selectedSession: SyncSession?

    enum HistoryTab: String, CaseIterable {
        case sessions = "Sync Sessions"
        case ledger = "Ledger Records"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.largeTitle.bold())
                Spacer()

                Picker("View", selection: $selectedTab) {
                    ForEach(HistoryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .help("Toggle between sync session history and individual ledger records")
            }
            .padding(24)

            Divider()

            // Content
            switch selectedTab {
            case .sessions:
                sessionsContent
            case .ledger:
                ledgerContent
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Sessions Content

    private var sessionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with summary stats
            if let summary {
                summarySection(summary)
            }

            Divider()

            // Session list
            if isLoading {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Ledger Content

    private var ledgerContent: some View {
        LedgerRecordsView()
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func summarySection(_ summary: SyncSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All-Time Statistics")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total Syncs",
                    value: "\(summary.totalSessions)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue
                )
                .help("Total number of sync sessions run since the app was first used")

                StatCard(
                    title: "Assets Uploaded",
                    value: "\(summary.totalUploaded)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                .help("Total assets successfully uploaded to Immich across all sessions")

                StatCard(
                    title: "Data Transferred",
                    value: summary.formattedBytesTransferred,
                    icon: "arrow.up.circle.fill",
                    color: .purple
                )
                .help("Total data uploaded to your Immich server")
            }

            if let lastSync = summary.lastSyncDate {
                Text("Last successful sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Sync History")
                .font(.headline)
            Text("Run your first sync to see history here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.headline)

            List(sessions, selection: $selectedSession) { session in
                SessionRow(session: session)
                    .tag(session)
            }
            .listStyle(.inset)
            .frame(minHeight: 200)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try await LedgerStore.shared.getSyncSessions(limit: 50)
            summary = try await LedgerStore.shared.getSyncSessionSummary()
        } catch {
            AppLogger.shared.error("Failed to load sync history: \(error.localizedDescription)", category: "UI")
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SyncSession

    var body: some View {
        HStack {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                    if session.isDryRun {
                        Text("DRY RUN")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.bytesTransferred > 0 {
                Text(ByteCountFormatter.string(fromByteCount: session.bytesTransferred, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            durationText
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case SyncSessionStatus.completed.rawValue:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case SyncSessionStatus.failed.rawValue:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case SyncSessionStatus.cancelled.rawValue:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        if session.totalUploaded > 0 {
            parts.append("\(session.totalUploaded) uploaded")
        }
        if session.totalSkipped > 0 {
            parts.append("\(session.totalSkipped) skipped")
        }
        if session.totalFailed > 0 {
            parts.append("\(session.totalFailed) failed")
        }
        if parts.isEmpty {
            parts.append("\(session.totalScanned) scanned")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var durationText: some View {
        if let completedAt = session.completedAt {
            let duration = completedAt.timeIntervalSince(session.startedAt)
            Text(formatDuration(duration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else if duration < 3600 {
            let mins = Int(duration / 60)
            let secs = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(duration / 3600)
            let mins = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }
}

// MARK: - SyncSession Hashable Conformance

extension SyncSession: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SyncSession, rhs: SyncSession) -> Bool {
        lhs.id == rhs.id
    }
}
