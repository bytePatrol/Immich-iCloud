import SwiftUI

struct ConflictReviewView: View {
    @Environment(AppState.self) private var appState
    @State private var conflicts: [SyncConflict] = []
    @State private var isLoading = false
    @State private var selectedConflict: SyncConflict?
    @State private var showResolved = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()
                .background(.bar)

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading conflicts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conflicts.isEmpty {
                emptyState
            } else {
                conflictList
            }
        }
        .task {
            await loadConflicts()
        }
        .sheet(item: $selectedConflict) { conflict in
            ConflictDetailView(conflict: conflict) {
                await loadConflicts()
                await appState.refreshConflictCount()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Conflicts")
                    .font(.headline)
                Text("\(unresolvedCount) unresolved conflicts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Show Resolved", isOn: $showResolved)
                .toggleStyle(.checkbox)
                .onChange(of: showResolved) { _, _ in
                    Task { await loadConflicts() }
                }
                .help("Include resolved conflicts in the list")

            Button {
                Task { await loadConflicts() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reload conflicts from the database")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No Conflicts")
                .font(.headline)
            Text("Run server reconciliation to detect conflicts between your local ledger and Immich server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conflict List

    private var conflictList: some View {
        List(conflicts, selection: $selectedConflict) { conflict in
            ConflictRow(conflict: conflict)
                .tag(conflict)
        }
        .listStyle(.inset)
    }

    // MARK: - Helpers

    private var unresolvedCount: Int {
        conflicts.filter { $0.resolvedAt == nil }.count
    }

    private func loadConflicts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if showResolved {
                conflicts = try await LedgerStore.shared.getAllConflicts()
            } else {
                conflicts = try await LedgerStore.shared.getUnresolvedConflicts()
            }
        } catch {
            AppLogger.shared.error("Failed to load conflicts: \(error.localizedDescription)", category: "UI")
        }
    }
}

// MARK: - Conflict Row

private struct ConflictRow: View {
    let conflict: SyncConflict

    var body: some View {
        HStack {
            // Status icon
            if conflict.resolvedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: conflict.typeEnum?.icon ?? "exclamationmark.circle")
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.localAssetId)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(conflict.typeEnum?.displayName ?? conflict.conflictType)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Detected: \(conflict.detectedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let resolution = conflict.resolutionEnum {
                        Text(resolution.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        switch conflict.typeEnum {
        case .checksumMismatch: return .purple
        case .missingOnServer: return .red
        case .orphanedOnServer: return .orange
        case .none: return .gray
        }
    }
}

// MARK: - SyncConflict Hashable

extension SyncConflict: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SyncConflict, rhs: SyncConflict) -> Bool {
        lhs.id == rhs.id
    }
}
