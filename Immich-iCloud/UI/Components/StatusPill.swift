import SwiftUI

struct StatusPill: View {
    let status: AssetStatus

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
            .help(statusDescription)
    }

    private var statusDescription: String {
        switch status {
        case .new: return "New — discovered in Photos but not yet processed"
        case .uploaded: return "Uploaded — successfully sent to Immich and recorded in ledger"
        case .blocked: return "Blocked — duplicate content fingerprint found under a different ID"
        case .ignored: return "Ignored — excluded by filter rules"
        case .failed: return "Failed — upload encountered an error, will retry on next sync"
        }
    }

    private var label: String {
        switch status {
        case .new: return "New"
        case .uploaded: return "Uploaded"
        case .blocked: return "Blocked"
        case .ignored: return "Ignored"
        case .failed: return "Failed"
        }
    }

    private var color: Color {
        switch status {
        case .new: return .blue
        case .uploaded: return .green
        case .blocked: return .orange
        case .ignored: return .gray
        case .failed: return .red
        }
    }
}
