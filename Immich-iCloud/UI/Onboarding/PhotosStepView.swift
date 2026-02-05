import SwiftUI
import Photos

struct PhotosStepView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Photos Library Access")
                .font(.title.bold())

            Text("Immich-iCloud needs read access to your Photos library to scan and upload assets.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            statusView

            if appState.photosAuthorization != .authorized && appState.photosAuthorization != .limited {
                Button("Request Access") {
                    Task {
                        await appState.requestPhotosAccess()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch appState.photosAuthorization {
        case .authorized:
            Label("Full access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .limited:
            Label("Limited access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
        case .denied:
            Label("Access denied — open System Settings to grant access", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        case .restricted:
            Label("Access restricted by device policy", systemImage: "lock.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        default:
            Label("Not yet requested", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
