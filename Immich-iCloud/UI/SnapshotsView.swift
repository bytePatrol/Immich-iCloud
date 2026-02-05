import SwiftUI

struct SnapshotsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var snapshots: [SnapshotInfo] = []
    @State private var isLoading = false
    @State private var snapshotToRestore: SnapshotInfo?
    @State private var showRestoreAlert = false
    @State private var showRestartAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Database Snapshots")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close this window (Escape)")
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading snapshots...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Snapshots")
                        .font(.headline)
                    Text("Snapshots are created automatically every hour.\nThe first snapshot will appear after one hour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(snapshots) { snapshot in
                        snapshotRow(snapshot)
                    }
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadSnapshots()
        }
        .alert("Restore Snapshot?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) {
                snapshotToRestore = nil
            }
            Button("Restore", role: .destructive) {
                if let snapshot = snapshotToRestore {
                    restoreSnapshot(snapshot)
                }
            }
        } message: {
            if let snapshot = snapshotToRestore {
                Text("This will replace your current database with the snapshot from \(snapshot.formattedDate).\n\nA backup of your current database will be created before restoring.\n\nThe app must be restarted after restoring.")
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Quit Now") {
                NSApplication.shared.terminate(nil)
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The snapshot has been restored. Please restart the app for the changes to take effect.")
        }
    }

    private func snapshotRow(_ snapshot: SnapshotInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.url.lastPathComponent)
                    .font(.body.monospaced())
                HStack(spacing: 12) {
                    Label(snapshot.formattedDate, systemImage: "clock")
                    Label(snapshot.formattedSize, systemImage: "doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Restore") {
                snapshotToRestore = snapshot
                showRestoreAlert = true
            }
            .buttonStyle(.bordered)
            .help("Restore this snapshot as the current database (requires app restart)")
        }
        .padding(.vertical, 4)
    }

    private func loadSnapshots() {
        isLoading = true
        snapshots = SnapshotManager.shared.listSnapshots()
        isLoading = false
    }

    private func restoreSnapshot(_ snapshot: SnapshotInfo) {
        Task {
            do {
                try await SnapshotManager.shared.restoreSnapshot(snapshot)
                errorMessage = nil
                showRestartAlert = true
            } catch {
                errorMessage = error.localizedDescription
            }
            snapshotToRestore = nil
        }
    }
}
