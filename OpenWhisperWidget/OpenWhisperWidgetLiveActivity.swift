import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import OpenWhisperShared

struct DictationLiveActivityView: View {
    let context: ActivityViewContext<DictationActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: phaseIcon)
                .font(.title3)
                .foregroundStyle(phaseColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle)
                    .font(.footnote.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if context.state.phase == .recording {
                Button(intent: StopDictationIntent()) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Link(destination: URL(string: "openwhisper://dictate")!) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 4)
    }

    private var phaseIcon: String {
        switch context.state.phase {
        case .recording: return "waveform"
        case .transcribing: return "ellipsis"
        case .done: return "checkmark.circle"
        }
    }

    private var phaseColor: Color {
        switch context.state.phase {
        case .recording: return .orange
        case .transcribing: return .secondary
        case .done: return .green
        }
    }

    private var phaseTitle: String {
        switch context.state.phase {
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .done: return "Done"
        }
    }

    private var subtitle: String {
        if let note = context.state.note, !note.isEmpty { return note }
        let total = Int(context.state.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct OpenWhisperWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            DictationLiveActivityView(context: context)
                .activityBackgroundTint(Color.orange.opacity(0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("OpenWhisper dictation")
                            .font(.footnote.weight(.semibold))
                        if context.state.phase == .transcribing {
                            Text("Transcribing…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .recording {
                        Button(intent: StopDictationIntent()) {
                            Label("Stop dictation", systemImage: "stop.circle.fill")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(compactTitle)
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "openwhisper://dictate"))
            .keylineTint(.orange)
        }
    }

    private var compactTitle: String {
        "OW"
    }
}

#Preview("Recording", as: .content, using: DictationActivityAttributes()) {
    OpenWhisperWidgetLiveActivity()
} contentStates: {
    DictationActivityAttributes.ContentState(phase: .recording, elapsed: 42)
}
