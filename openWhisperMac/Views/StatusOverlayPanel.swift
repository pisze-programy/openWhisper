import AppKit
import SwiftUI
import OpenWhisperShared

@MainActor
final class StatusOverlayPanel {
    static let shared = StatusOverlayPanel()

    var activeAppIcon: NSImage?
    var getSamples: (@MainActor () -> [Float])?

    private static let recordingPanelSize = NSSize(width: 280, height: 52)
    private static let stylePanelSize = NSSize(width: 380, height: 52)
    private static let messagePanelWidth: CGFloat = 380

    private var panel: NSPanel?
    private var hostingView: NSHostingView<StatusOverlayView>?
    private var styleHostingView: NSHostingView<StyleOverlayView>?
    private var styleGeneration = 0
    private var styleTask: Task<Void, Never>?
    private var currentStyle: TranscriptionStyle = .none
    private var currentOnConfirm: (() -> Void)?
    private var messageHostingView: NSHostingView<MessageOverlayView>?
    private var messageGeneration = 0
    private var messageTask: Task<Void, Never>?
    private var messageHeight: CGFloat = 52

    private init() {}

    func show(phase: DictationOrchestrator.Phase, title: String? = nil) {
        if panel == nil {
            createPanel()
        }
        cancelStyleOverlay()
        cancelMessage()
        hostingView?.rootView = StatusOverlayView(phase: phase, appIcon: activeAppIcon, titleOverride: title)
        if panel?.isVisible != true {
            animateShow(size: Self.recordingPanelSize)
        } else {
            positionAndShow(size: Self.recordingPanelSize)
            panel?.alphaValue = 1
        }
    }

    /// Shows a transient message (errors, hints, "No text selected", done
    /// states) that auto-hides after `duration` seconds.
    func showMessage(
        title: String,
        detail: String? = nil,
        icon: OverlayIcon = .info,
        tint: Color = .white,
        duration: TimeInterval = 1.6
    ) {
        messageGeneration += 1
        let generation = messageGeneration
        messageTask?.cancel()
        if panel == nil {
            createPanel()
        }
        cancelStyleOverlay()
        hostingView?.rootView = StatusOverlayView(phase: .idle, appIcon: nil)
        messageHostingView?.rootView = MessageOverlayView(title: title, detail: detail, icon: icon, tint: tint)
        messageHostingView?.isHidden = false
        messageHeight = detail == nil ? 52 : 68
        let size = NSSize(width: Self.messagePanelWidth, height: messageHeight)
        if panel?.isVisible != true {
            animateShow(size: size)
        } else {
            positionAndShow(size: size)
            panel?.alphaValue = 1
        }
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(duration * 1000))
            guard let self, self.messageGeneration == generation, !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Shows the style-switch overlay for a chosen style. After a short delay the
    /// style icon morphs into a green checkmark and `onConfirm` fires (the sound);
    /// then the overlay auto-hides. Rapid re-cycling replaces the overlay, which
    /// cancels the pending hide of the previous style.
    func showStyleSwitch(style: TranscriptionStyle, onConfirm: (() -> Void)? = nil) {
        styleGeneration += 1
        let generation = styleGeneration
        currentStyle = style
        currentOnConfirm = onConfirm
        styleTask?.cancel()
        if panel == nil {
            createPanel()
        }
        cancelMessage()
        hostingView?.rootView = StatusOverlayView(phase: .idle, appIcon: nil)
        styleHostingView?.rootView = StyleOverlayView(style: style, confirmed: false)
        styleHostingView?.isHidden = false
        if panel?.isVisible != true {
            animateShow(size: Self.stylePanelSize)
        } else {
            positionAndShow(size: Self.stylePanelSize)
            panel?.alphaValue = 1
        }
        scheduleStyleConfirmation(after: 900, generation: generation)
    }

    /// Called when the style-switch hotkey is released after cycling: skip
    /// straight to the confirmation (checkmark + sound) and close shortly after.
    /// The selection has already been persisted by the caller.
    func confirmStyleSelection() {
        styleTask?.cancel()
        let generation = styleGeneration
        guard panel?.isVisible == true, styleHostingView?.isHidden == false else { return }
        styleHostingView?.rootView = StyleOverlayView(style: currentStyle, confirmed: true)
        currentOnConfirm?()
        styleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.styleGeneration == generation, !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func scheduleStyleConfirmation(after delayMillis: Int, generation: Int) {
        styleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMillis))
            guard let self, self.styleGeneration == generation, !Task.isCancelled else { return }
            self.styleHostingView?.rootView = StyleOverlayView(style: self.currentStyle, confirmed: true)
            self.currentOnConfirm?()
            try? await Task.sleep(for: .milliseconds(450))
            guard self.styleGeneration == generation, !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Removes the pending style overlay (e.g. when a recording starts).
    /// Bumping the generation cancels the auto-hide task and invalidates any
    /// in-flight confirmation callback.
    private func cancelStyleOverlay() {
        styleGeneration += 1
        styleTask?.cancel()
        styleTask = nil
        styleHostingView?.rootView = StyleOverlayView(style: .none, confirmed: false)
        styleHostingView?.isHidden = true
    }

    /// Removes a pending message overlay.
    private func cancelMessage() {
        messageGeneration += 1
        messageTask?.cancel()
        messageTask = nil
        messageHostingView?.isHidden = true
    }

    func hide() {
        animateHide()
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.recordingPanelSize.width, height: Self.recordingPanelSize.height),
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

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: Self.recordingPanelSize.width, height: Self.recordingPanelSize.height))
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor

        let hostingView = NSHostingView(rootView: StatusOverlayView(phase: .idle, appIcon: nil))
        hostingView.frame = wrapper.bounds
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)

        let styleHostingView = NSHostingView(rootView: StyleOverlayView(style: .none, confirmed: false))
        styleHostingView.frame = wrapper.bounds
        styleHostingView.autoresizingMask = [.width, .height]
        styleHostingView.isHidden = true
        wrapper.addSubview(styleHostingView)

        let messageHostingView = NSHostingView(rootView: MessageOverlayView(title: "", detail: nil, icon: .info, tint: .white))
        messageHostingView.frame = wrapper.bounds
        messageHostingView.autoresizingMask = [.width, .height]
        messageHostingView.isHidden = true
        wrapper.addSubview(messageHostingView)

        panel.contentView = wrapper
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel = panel
        self.hostingView = hostingView
        self.styleHostingView = styleHostingView
        self.messageHostingView = messageHostingView
    }

    private func positionAndShow(size: NSSize) {
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        panel.orderFrontRegardless()
    }

    private func animateShow(size: NSSize) {
        guard let panel else { return }
        positionAndShow(size: size)
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
    var titleOverride: String?

    init(phase: DictationOrchestrator.Phase, appIcon: NSImage?, titleOverride: String? = nil) {
        self.phase = phase
        self.appIcon = appIcon
        self.titleOverride = titleOverride
    }

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

            if case .listening = phase, titleOverride == nil {
                if let getSamples = StatusOverlayPanel.shared.getSamples {
                    LiveWaveformOverlay(getSamples: getSamples)
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
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
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
            let samples = getSamples()
            let raw = WaveformBars.bars(from: samples, count: 22)
            let level = Self.level(of: samples)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<raw.count, id: \.self) { i in
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: Self.barHeight(bar: raw[i], index: i, count: raw.count, level: level))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.12), value: raw)
        }
    }

    /// Global amplitude 0...1 for the visible window. Silence → low floor so the
    /// whole wave stays flat and short; speech → rises and drives the bars.
    private static func level(of samples: [Float]) -> CGFloat {
        let window = Array(samples.suffix(4096))
        guard !window.isEmpty else { return 0.05 }
        var peak: Float = 0
        for s in window {
            let a = abs(s)
            if a > peak { peak = a }
        }
        return max(min(CGFloat(peak) / 0.3, 1), 0.05)
    }

    /// Bar height = per-segment peak × mild edge envelope × global level.
    /// Cap keeps it inside the pill; floor keeps a subtle idle wave in silence.
    private static func barHeight(bar: CGFloat, index: Int, count: Int, level: CGFloat) -> CGFloat {
        let envelope = 0.55 + 0.45 * CGFloat(sin(Double.pi * Double(index + 1) / Double(count + 1)))
        return max(min(bar * envelope * level, 16), 2.5)
    }
}

/// Transient confirmation shown while cycling styles with the hotkey. The style
/// icon occupies a single slot and morphs into a green checkmark right before
/// the overlay closes. Pure presentation — the timing lives in the panel, which
/// swaps `confirmed` and hides the overlay.
private struct StyleOverlayView: View {
    let style: TranscriptionStyle
    let confirmed: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(style.whenToUse)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Image(systemName: confirmed ? "checkmark.circle.fill" : style.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(confirmed ? .green : .white)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
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
}

/// Icon used by transient message overlays.
enum OverlayIcon {
    case check
    case warning
    case error
    case info

    var systemImage: String {
        switch self {
        case .check: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle"
        }
    }
}

/// Transient message (error, hint, result state). Pure presentation — the
/// panel owns the timing and swaps this view in and out.
private struct MessageOverlayView: View {
    let title: String
    let detail: String?
    let icon: OverlayIcon
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Image(systemName: icon.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
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
}

