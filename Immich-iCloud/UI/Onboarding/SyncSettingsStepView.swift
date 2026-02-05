import SwiftUI

struct SyncSettingsStepView: View {
    @Environment(AppState.self) private var appState
    @State private var showStartDate = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Sync Settings")
                .font(.title.bold())

            Text("Configure how your first sync will run.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                // Start Date
                Toggle("Enable Start Date Filter", isOn: $showStartDate)
                    .onChange(of: showStartDate) { _, enabled in
                        if !enabled {
                            appState.config.startDate = nil
                        } else if appState.config.startDate == nil {
                            appState.config.startDate = Date()
                        }
                    }

                if showStartDate {
                    DatePicker(
                        "Only sync photos after:",
                        selection: Binding(
                            get: { appState.config.startDate ?? Date() },
                            set: { appState.config.startDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .frame(maxWidth: 350)
                }

                Divider()

                // Dry Run
                Toggle("Start with Dry Run (recommended)", isOn: $appState.config.isDryRun)

                if appState.config.isDryRun {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Dry Run scans and logs but uploads nothing. You can disable it later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding()
        .onAppear {
            showStartDate = appState.config.startDate != nil
        }
    }
}
