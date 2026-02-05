import SwiftUI

struct DryRunBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Text("Dry Run Mode")
                .font(.subheadline.bold())
            Text("— No uploads or ledger writes will occur")
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 10))
        .help("Dry Run mode is enabled — no data will be uploaded and no ledger records will be written. Disable in Settings > Sync Configuration.")
    }
}
