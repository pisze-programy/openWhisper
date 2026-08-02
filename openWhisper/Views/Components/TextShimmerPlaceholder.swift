import SwiftUI
import OpenWhisperShared

/// A gray, shimmering placeholder shown while a note is being rewritten by AI.
/// Draws a few skeleton lines with a moving highlight sweeping left → right,
/// then the real text fades in to replace it.
struct TextShimmerPlaceholder: View {
    private static let lineFractions: [CGFloat] = [0.95, 0.8, 0.5]

    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<Self.lineFractions.count, id: \.self) { index in
                    skeletonLine(width: width * Self.lineFractions[index], containerWidth: width)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 52)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func skeletonLine(width: CGFloat, containerWidth: CGFloat) -> some View {
        Capsule()
            .fill(.quaternary)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: containerWidth * 0.4)
                .offset(x: (phase * containerWidth * 1.6) - containerWidth * 0.4)
                .mask {
                    Capsule().fill(.black)
                }
            }
            .frame(width: width, height: 12)
    }
}

struct TextShimmerPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        TextShimmerPlaceholder()
            .padding()
    }
}
