import SwiftUI

struct VideoPlaceholder: View {
    let caption: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
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
