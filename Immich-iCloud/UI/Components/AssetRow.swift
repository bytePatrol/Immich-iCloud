import SwiftUI

struct AssetRow: View {
    let asset: AssetSummary

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail = asset.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: asset.mediaType == .video ? "video.fill" : "photo")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                // Video duration badge
                if let dur = asset.formattedDuration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(dur)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let date = asset.creationDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let size = asset.formattedFileSize {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let res = asset.resolution {
                        Text(res)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            StatusPill(status: asset.status)
        }
        .padding(.vertical, 4)
    }
}
