import SwiftUI

public struct LiveWaveform: View {
    public let getSamples: @MainActor () -> [Float]

    public init(getSamples: @escaping @MainActor () -> [Float]) {
        self.getSamples = getSamples
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { _ in
            let bars = WaveformBars.bars(from: getSamples())
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { i in
                    Capsule()
                        .fill(AppTheme.accent.opacity(0.75))
                        .frame(width: 4, height: bars[i])
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.12), value: bars)
        }
    }
}
