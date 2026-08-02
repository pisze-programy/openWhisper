import SwiftUI
import OpenWhisperShared

struct VideoPlaceholder: View {
    let caption: String

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
    }
}

#Preview {
    VideoPlaceholder(caption: "Demo video coming soon")
        .padding()
}
