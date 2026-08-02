import AppKit
import SwiftUI
import OpenWhisperShared

@MainActor
final class StatusOverlayPanel {
    static let shared = StatusOverlayPanel()

    var activeAppIcon: NSImage?
    var getSamples: (@MainActor () -> [Float])?

    private var panel: NSPanel?
    private var hostingView: NSHostingView<StatusOverlayView>?

    private init() {}

    func show(phase: DictationOrchestrator.Phase) {
        if panel == nil {
            createPanel()
        }
        hostingView?.rootView = StatusOverlayView(phase: phase, appIcon: activeAppIcon)
        if panel?.isVisible != true {
            animateShow()
        }
    }

    func hide() {
        animateHide()
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 52),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor
        let hostingView = NSHostingView(rootView: StatusOverlayView(phase: .idle, appIcon: nil))
        hostingView.frame = wrapper.bounds
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)
        panel.contentView = wrapper
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel = panel
        self.hostingView = hostingView
    }

    private func positionAndShow() {
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let size = NSSize(width: 280, height: 52)
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        panel.orderFrontRegardless()
    }

    private func animateShow() {
        guard let panel else { return }
        positionAndShow()
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    private func animateHide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

struct StatusOverlayView: View {
    let phase: DictationOrchestrator.Phase
    let appIcon: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer().frame(width: 12)
            }

            if case .listening = phase {
                if let getSamples = StatusOverlayPanel.shared.getSamples {
                    LiveWaveformOverlay(getSamples: getSamples)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Listening")
                        .font(.system(size: 15, weight: .semibold))
                }
            } else {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer()

            Image(systemName: rightIcon)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(rightIconColor)
                .frame(width: 22)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .compositingGroup()
        .background {
            ZStack {
                Capsule()
                    .fill(.black.opacity(0.3))
                    .blur(radius: 16)
                    .offset(y: 3)

                Capsule()
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var title: String {
        switch phase {
        case .idle: return ""
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .polishing: return "Polishing"
        case .done: return "Copied"
        case .failed: return "Error"
        }
    }

    private var rightIcon: String {
        switch phase {
        case .idle: return "waveform"
        case .listening: return "mic.fill"
        case .transcribing, .polishing: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var rightIconColor: Color {
        switch phase {
        case .idle: return .secondary.opacity(0.6)
        case .listening: return .white
        case .transcribing, .polishing: return .white
        case .done: return .green
        case .failed: return .orange
        }
    }
}

private struct LiveWaveformOverlay: View {
    let getSamples: @MainActor () -> [Float]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { _ in
            let bars = WaveformBars.bars(from: getSamples())
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { i in
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: bars[i])
                }
            }
            .animation(.easeInOut(duration: 0.12), value: bars)
        }
    }
}
