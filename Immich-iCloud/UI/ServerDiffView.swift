import SwiftUI

struct ServerDiffView: View {
    @Environment(AppState.self) private var appState
    @State private var result: ReconciliationEngine.ReconciliationResult?
    @State private var isLoading = false
    @State private var selectedTab = DiffTab.orphaned
    @State private var errorMessage: String?
    @State private var selectedOrphanIds: Set<String> = []
    @State private var isDeleting = false

    enum DiffTab: String, CaseIterable {
        case orphaned = "Orphaned"
        case missing = "Missing"
        case mismatches = "Mismatches"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()
                .background(.bar)

            Divider()

            // Content
            if isLoading {
                ProgressView("Running reconciliation...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                resultView(result)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Server Reconciliation")
                    .font(.headline)
                Text("Compare local ledger with Immich server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await runReconciliation() }
            } label: {
                Label(result == nil ? "Run Reconciliation" : "Refresh", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isLoading || !appState.hasValidCredentials)
            .help("Compare your local ledger with assets on the Immich server to find discrepancies")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Server Reconciliation")
                .font(.headline)
            Text("Click 'Run Reconciliation' to compare your local ledger with assets on the Immich server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !appState.hasValidCredentials {
                Text("Configure Immich server credentials first.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(_ result: ReconciliationEngine.ReconciliationResult) -> some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorBanner(error)
                    .padding()
            }

            // Summary
            summaryBar(result)
                .padding()

            Divider()

            // Tab picker
            Picker("Category", selection: $selectedTab) {
                ForEach(DiffTab.allCases, id: \.self) { tab in
                    Text("\(tab.rawValue) (\(countForTab(tab, result: result)))")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch selectedTab {
                    case .orphaned:
                        orphanedContent(result.orphanedOnServer)
                    case .missing:
                        missingContent(result.missingFromServer)
                    case .mismatches:
                        mismatchesContent(result.checksumMismatches)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(_ result: ReconciliationEngine.ReconciliationResult) -> some View {
        HStack(spacing: 24) {
            summaryItem(
                title: "Orphaned",
                count: result.orphanedOnServer.count,
                icon: "questionmark.circle.fill",
                color: .orange,
                tooltip: "Assets on Immich server that are not tracked in your local ledger"
            )
            summaryItem(
                title: "Missing",
                count: result.missingFromServer.count,
                icon: "exclamationmark.triangle.fill",
                color: .red,
                tooltip: "Assets in your ledger that no longer exist on the Immich server"
            )
            summaryItem(
                title: "Mismatches",
                count: result.checksumMismatches.count,
                icon: "arrow.triangle.2.circlepath.circle.fill",
                color: .purple,
                tooltip: "Assets with different checksums between ledger and server"
            )
            Spacer()

            if result.totalIssues == 0 {
                Label("All synced", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())
                    .help("Your local ledger is fully synchronized with the Immich server")
            }
        }
    }

    private func summaryItem(title: String, count: Int, icon: String, color: Color, tooltip: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? color : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(tooltip)
    }

    // MARK: - Orphaned Content

    @ViewBuilder
    private func orphanedContent(_ assets: [ImmichAssetSummary]) -> some View {
        if assets.isEmpty {
            emptyTabState("No orphaned assets found. All server assets are tracked in your ledger.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Assets on server not in local ledger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    if !selectedOrphanIds.isEmpty {
                        Button("Delete Selected (\(selectedOrphanIds.count))") {
                            Task { await deleteSelectedOrphans() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(isDeleting)
                        .help("Permanently delete selected orphaned assets from the Immich server")
                    }

                    Button(selectedOrphanIds.count == assets.count ? "Deselect All" : "Select All") {
                        if selectedOrphanIds.count == assets.count {
                            selectedOrphanIds.removeAll()
                        } else {
                            selectedOrphanIds = Set(assets.map { $0.id })
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(selectedOrphanIds.count == assets.count ? "Deselect all orphaned assets" : "Select all orphaned assets for deletion")
                }

                ForEach(assets) { asset in
                    orphanedAssetRow(asset)
                }
            }
        }
    }

    private func orphanedAssetRow(_ asset: ImmichAssetSummary) -> some View {
        HStack {
            Button {
                if selectedOrphanIds.contains(asset.id) {
                    selectedOrphanIds.remove(asset.id)
                } else {
                    selectedOrphanIds.insert(asset.id)
                }
            } label: {
                Image(systemName: selectedOrphanIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedOrphanIds.contains(asset.id) ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.originalFileName ?? asset.id)
                    .font(.body)
                HStack(spacing: 8) {
                    Text("ID: \(asset.id.prefix(12))...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let type = asset.type {
                        Text(type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Missing Content

    @ViewBuilder
    private func missingContent(_ records: [LedgerRecord]) -> some View {
        if records.isEmpty {
            emptyTabState("No missing assets. All ledger entries exist on the server.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assets in ledger but deleted from server")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(records, id: \.localAssetId) { record in
                    missingAssetRow(record)
                }
            }
        }
    }

    private func missingAssetRow(_ record: LedgerRecord) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.localAssetId)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let immichId = record.immichAssetId {
                        Text("Was: \(immichId.prefix(12))...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let date = record.firstUploadedAt {
                        Text("Uploaded: \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Future: Add re-upload button
        }
        .padding(.vertical, 4)
    }

    // MARK: - Mismatches Content

    @ViewBuilder
    private func mismatchesContent(_ mismatches: [(local: LedgerRecord, server: ImmichAssetSummary)]) -> some View {
        if mismatches.isEmpty {
            emptyTabState("No checksum mismatches found. All synced assets match the server.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assets with different content on server vs local")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(mismatches, id: \.local.localAssetId) { mismatch in
                    mismatchRow(mismatch)
                }
            }
        }
    }

    private func mismatchRow(_ mismatch: (local: LedgerRecord, server: ImmichAssetSummary)) -> some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text(mismatch.local.localAssetId)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("Local: \(mismatch.local.fingerprint?.prefix(12) ?? "none")...")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("Server: \(mismatch.server.checksum?.prefix(12) ?? "none")...")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func emptyTabState(_ message: String) -> some View {
        VStack {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func countForTab(_ tab: DiffTab, result: ReconciliationEngine.ReconciliationResult) -> Int {
        switch tab {
        case .orphaned: return result.orphanedOnServer.count
        case .missing: return result.missingFromServer.count
        case .mismatches: return result.checksumMismatches.count
        }
    }

    // MARK: - Actions

    private func runReconciliation() async {
        guard appState.hasValidCredentials else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let engine = ReconciliationEngine(baseURL: appState.serverURL, apiKey: appState.apiKey)
            result = try await engine.reconcile()
            selectedOrphanIds.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedOrphans() async {
        guard !selectedOrphanIds.isEmpty, appState.hasValidCredentials else { return }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let engine = ReconciliationEngine(baseURL: appState.serverURL, apiKey: appState.apiKey)
            try await engine.deleteOrphanedAssets(ids: Array(selectedOrphanIds))
            // Re-run reconciliation to refresh
            await runReconciliation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
