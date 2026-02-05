import SwiftUI

struct LedgerRecordsView: View {
    @Environment(AppState.self) private var appState

    @State private var records: [LedgerRecord] = []
    @State private var filterStatus: AssetStatus? = nil
    @State private var isLoading = false

    private var filteredRecords: [LedgerRecord] {
        guard let status = filterStatus else { return records }
        return records.filter { $0.status == status.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ledger Records")
                    .font(.headline)
                Spacer()

                Picker("Status", selection: $filterStatus) {
                    Text("All").tag(AssetStatus?.none)
                    Text("Uploaded").tag(AssetStatus?.some(.uploaded))
                    Text("Failed").tag(AssetStatus?.some(.failed))
                    Text("Blocked").tag(AssetStatus?.some(.blocked))
                }
                .frame(width: 120)
                .help("Filter records by upload status")

                Button {
                    Task { await loadRecords() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Reload all records from the ledger database")
            }
            .padding(24)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading records...")
                Spacer()
            } else if filteredRecords.isEmpty {
                Spacer()
                if records.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Upload History",
                        message: "Completed uploads will appear here with their status and metadata."
                    )
                } else {
                    EmptyStateView(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No Matching Records",
                        message: "No records match the selected filter."
                    )
                }
                Spacer()
            } else {
                List(filteredRecords, id: \.localAssetId) { record in
                    HStack(spacing: 12) {
                        statusIcon(for: record.status)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.localAssetId)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if let date = record.firstUploadedAt {
                                    Label(
                                        date.formatted(date: .abbreviated, time: .shortened),
                                        systemImage: "calendar"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Label(
                                    record.mediaType.capitalized,
                                    systemImage: record.mediaType == "video" ? "video" : "photo"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                                if record.uploadAttemptCount > 1 {
                                    Text("\(record.uploadAttemptCount) attempts")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        Spacer()

                        if let immichId = record.immichAssetId {
                            Text(String(immichId.prefix(8)))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }

                        if let error = record.errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .frame(maxWidth: 200, alignment: .trailing)
                                .help(error)
                        }

                        StatusPill(status: AssetStatus(rawValue: record.status) ?? .new)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)

                HStack {
                    Text("\(filteredRecords.count) of \(records.count) records")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }
        }
        .task {
            await loadRecords()
        }
    }

    private func loadRecords() async {
        isLoading = true
        do {
            records = try await LedgerStore.shared.allRecords()
        } catch {
            AppLogger.shared.error("Failed to load history: \(error.localizedDescription)", category: "History")
            records = []
        }
        isLoading = false
    }

    private func statusIcon(for status: String) -> some View {
        Image(systemName: iconName(for: status))
            .font(.caption)
            .foregroundStyle(colorForStatus(status))
            .frame(width: 16)
    }

    private func iconName(for status: String) -> String {
        switch AssetStatus(rawValue: status) {
        case .uploaded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .blocked: return "hand.raised.fill"
        case .ignored: return "eye.slash.fill"
        case .new, .none: return "circle"
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch AssetStatus(rawValue: status) {
        case .uploaded: return .green
        case .failed: return .red
        case .blocked: return .orange
        case .ignored: return .gray
        case .new, .none: return .blue
        }
    }
}
