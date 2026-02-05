import SwiftUI

struct ServerStepView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL: String = ""
    @State private var apiKey: String = ""
    @State private var connectionStatus: ServerConnectionStatus = .untested

    private enum ServerConnectionStatus {
        case untested
        case testing
        case success(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Connect to Immich")
                .font(.title.bold())

            Text("Enter your Immich server URL and API key.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("https://immich.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)

                HStack(spacing: 12) {
                    Button("Save & Test") {
                        saveAndTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverURL.isEmpty || apiKey.isEmpty)

                    connectionLabel
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            serverURL = appState.serverURL
            apiKey = appState.apiKey
        }
    }

    @ViewBuilder
    private var connectionLabel: some View {
        switch connectionStatus {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Testing...").font(.caption).foregroundStyle(.secondary)
            }
        case .success(let version):
            Label("Connected (\(version))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func saveAndTest() {
        appState.serverURL = serverURL
        Task {
            await appState.saveAPIKey(apiKey)
        }

        connectionStatus = .testing
        Task {
            let client = ImmichClient(baseURL: serverURL, apiKey: apiKey)
            do {
                let info = try await client.testConnection()
                connectionStatus = .success(info.version)
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }
}
