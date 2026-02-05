import SwiftUI

struct ConflictDetailView: View {
    let conflict: SyncConflict
    let onResolved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResolution: ConflictResolution?
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()
                .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    conflictInfo
                    comparisonSection
                    resolutionSection
                }
                .padding()
            }

            Divider()

            // Actions
            actionBar
                .padding()
                .background(.bar)
        }
        .frame(width: 500, height: 500)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: conflict.typeEnum?.icon ?? "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.typeEnum?.displayName ?? "Conflict")
                    .font(.headline)
                Text("Detected \(conflict.detectedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if conflict.resolvedAt != nil {
                Label("Resolved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Conflict Info

    private var conflictInfo: some View {
        GroupBox("Asset Information") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Local Asset ID", value: conflict.localAssetId)

                if let immichId = conflict.immichAssetId {
                    infoRow(label: "Immich Asset ID", value: immichId)
                }

                infoRow(label: "Conflict Type", value: conflict.typeEnum?.displayName ?? conflict.conflictType)
            }
            .padding(.vertical, 4)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Comparison Section

    @ViewBuilder
    private var comparisonSection: some View {
        if conflict.localFingerprint != nil || conflict.serverChecksum != nil {
            GroupBox("Content Comparison") {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local Fingerprint")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        Text(conflict.localFingerprint ?? "N/A")
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Checksum")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(conflict.serverChecksum ?? "N/A")
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Resolution Section

    private var resolutionSection: some View {
        GroupBox("Resolution") {
            VStack(alignment: .leading, spacing: 12) {
                if conflict.resolvedAt != nil {
                    if let resolution = conflict.resolutionEnum {
                        Label(resolution.displayName, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Choose how to resolve this conflict:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(applicableResolutions, id: \.self) { resolution in
                        resolutionOption(resolution)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func resolutionOption(_ resolution: ConflictResolution) -> some View {
        Button {
            selectedResolution = resolution
        } label: {
            HStack {
                Image(systemName: selectedResolution == resolution ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedResolution == resolution ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolution.displayName)
                        .font(.body)
                    Text(resolution.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var applicableResolutions: [ConflictResolution] {
        switch conflict.typeEnum {
        case .checksumMismatch:
            return [.reUpload, .skip, .keepBoth]
        case .missingOnServer:
            return [.reUpload, .skip]
        case .orphanedOnServer:
            return [.deleteServer, .skip]
        case .none:
            return ConflictResolution.allCases
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            if conflict.resolvedAt == nil {
                Button("Apply Resolution") {
                    Task { await applyResolution() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedResolution == nil || isResolving)
            } else {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func applyResolution() async {
        guard let resolution = selectedResolution,
              let conflictId = conflict.id else { return }

        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            // TODO: Execute the actual resolution action (re-upload, delete, etc.)
            // For now, just mark as resolved
            try await LedgerStore.shared.resolveConflict(id: conflictId, resolution: resolution)
            AppLogger.shared.info("Conflict \(conflictId) resolved with: \(resolution.rawValue)", category: "Conflict")
            await onResolved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var iconColor: Color {
        switch conflict.typeEnum {
        case .checksumMismatch: return .purple
        case .missingOnServer: return .red
        case .orphanedOnServer: return .orange
        case .none: return .gray
        }
    }
}
