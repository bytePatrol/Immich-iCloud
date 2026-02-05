import SwiftUI

struct ReadyStepView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            // Summary
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(icon: "server.rack", label: "Server", value: appState.serverURL.isEmpty ? "Not configured" : appState.serverURL)
                summaryRow(icon: "key", label: "API Key", value: appState.apiKey.isEmpty ? "Not set" : "Configured")
                summaryRow(icon: "photo.stack", label: "Photos Access", value: photosStatusText)
                summaryRow(icon: "calendar", label: "Start Date", value: appState.config.startDate.map { Self.dateFormatter.string(from: $0) } ?? "None")
                summaryRow(icon: "flask", label: "Dry Run", value: appState.config.isDryRun ? "Enabled" : "Disabled")
            }
            .padding()
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button {
                    appState.config.onboardingComplete = true
                    appState.selectedTab = .sync
                    Task {
                        let engine = SyncEngine(appState: appState)
                        await engine.startSync()
                    }
                } label: {
                    Label("Start First Sync", systemImage: "play.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.hasValidCredentials)

                Button {
                    appState.config.onboardingComplete = true
                } label: {
                    Label("Go to Dashboard", systemImage: "square.grid.2x2")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline.bold())
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private var photosStatusText: String {
        switch appState.photosAuthorization {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Denied"
        default: return "Not requested"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
