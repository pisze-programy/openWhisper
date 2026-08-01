import OpenWhisperShared
import SwiftUI

struct LiveWaveform: View {
    let getSamples: @MainActor () -> [Float]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { _ in
            let bars = WaveformBars.bars(from: getSamples())
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { i in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: 4, height: bars[i])
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.12), value: bars)
        }
    }
}
