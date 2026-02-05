import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Welcome to Immich-iCloud")
                .font(.largeTitle.bold())

            Text("Sync your iCloud Photos library to your self-hosted Immich server.\nUpload once, never re-upload. Your ledger keeps track of everything.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .padding()
    }
}
