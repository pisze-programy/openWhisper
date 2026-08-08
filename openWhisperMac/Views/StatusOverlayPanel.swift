import AppKit
import SwiftUI
import OpenWhisperShared

@MainActor
final class StatusOverlayPanel {
    static let shared = StatusOverlayPanel()

    var activeAppIcon: NSImage?
    var getSamples: (@MainActor () -> [Float])?

    private static let recordingPanelSize = NSSize(width: 280, height: 52)
    private static let selectorPanelSize = NSSize(width: 380, height: 52)
    private static let messagePanelWidth: CGFloat = 380

    private var panel: NSPanel?
    private var hostingView: NSHostingView<StatusOverlayView>?
    private var selectorHostingView: NSHostingView<SelectorOverlayView>?
    private var selectorGeneration = 0
    private var selectorTask: Task<Void, Never>?
    private var currentSelector: SelectorOverlayContent?
    private var currentSelectorOnConfirm: (() -> Void)?
    private var messageHostingView: NSHostingView<MessageOverlayView>?
    private var messageGeneration = 0
    private var messageTask: Task<Void, Never>?
    private var messageHeight: CGFloat = 52

    private init() {}

    /// Content shown by the shared cycling-selector overlay (style or
    /// translation target) — the only thing that changes between the two.
    private struct SelectorOverlayContent {
        let title: String
        let subtitle: String
        let systemImage: String
    }

    func show(phase: DictationOrchestrator.Phase, title: String? = nil) {
        if panel == nil {
            createPanel()
        }
        cancelSelectorOverlay()
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
        cancelSelectorOverlay()
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

    // MARK: - Selector overlay (shared by style & translation cycles)

    /// Shows the style-switch overlay for a chosen style.
    func showStyleSwitch(style: TranscriptionStyle, onConfirm: (() -> Void)? = nil) {
        showSelector(
            title: style.title,
            subtitle: style.whenToUse,
            systemImage: style.systemImage,
            onConfirm: onConfirm
        )
    }

    /// Shows the translation-switch overlay for the current target (`nil` =
    /// None). Same component as the style switch — only the content changes.
    func showTranslationSwitch(target: String?, onConfirm: (() -> Void)? = nil) {
        let language = Language.language(for: target)
        showSelector(
            title: language?.name ?? "None",
            subtitle: language == nil ? "No translation — STT language output" : "Target language",
            systemImage: "globe",
            onConfirm: onConfirm
        )
    }

    /// Displays the cycling-selector overlay. After a short delay the icon
    /// morphs into a green checkmark and `onConfirm` fires (the sound); then the
    /// overlay auto-hides. Rapid re-cycling replaces the overlay, which cancels
    /// the pending hide of the previous selection.
    private func showSelector(
        title: String,
        subtitle: String,
        systemImage: String,
        onConfirm: (() -> Void)?
    ) {
        selectorGeneration += 1
        let generation = selectorGeneration
        currentSelector = SelectorOverlayContent(title: title, subtitle: subtitle, systemImage: systemImage)
        currentSelectorOnConfirm = onConfirm
        selectorTask?.cancel()
        if panel == nil {
            createPanel()
        }
        cancelMessage()
        hostingView?.rootView = StatusOverlayView(phase: .idle, appIcon: nil)
        selectorHostingView?.rootView = SelectorOverlayView(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            confirmed: false
        )
        selectorHostingView?.isHidden = false
        if panel?.isVisible != true {
            animateShow(size: Self.selectorPanelSize)
        } else {
            positionAndShow(size: Self.selectorPanelSize)
            panel?.alphaValue = 1
        }
        scheduleSelectorConfirmation(after: 900, generation: generation)
    }

    /// Called when the cycling hotkey is released: skip straight to the
    /// confirmation (checkmark + sound) and close shortly after. The selection
    /// has already been persisted by the caller.
    func confirmSelectorSelection() {
        selectorTask?.cancel()
        let generation = selectorGeneration
        guard panel?.isVisible == true, selectorHostingView?.isHidden == false, let currentSelector else { return }
        selectorHostingView?.rootView = SelectorOverlayView(
            title: currentSelector.title,
            subtitle: currentSelector.subtitle,
            systemImage: currentSelector.systemImage,
            confirmed: true
        )
        currentSelectorOnConfirm?()
        selectorTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.selectorGeneration == generation, !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func scheduleSelectorConfirmation(after delayMillis: Int, generation: Int) {
        selectorTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMillis))
            guard let self, self.selectorGeneration == generation, let currentSelector, !Task.isCancelled else { return }
            self.selectorHostingView?.rootView = SelectorOverlayView(
                title: currentSelector.title,
                subtitle: currentSelector.subtitle,
                systemImage: currentSelector.systemImage,
                confirmed: true
            )
            self.currentSelectorOnConfirm?()
            try? await Task.sleep(for: .milliseconds(450))
            guard self.selectorGeneration == generation, !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Removes a pending selector overlay (e.g. when a recording starts).
    /// Bumping the generation cancels the auto-hide task and invalidates any
    /// in-flight confirmation callback.
    private func cancelSelectorOverlay() {
        selectorGeneration += 1
        selectorTask?.cancel()
        selectorTask = nil
        currentSelector = nil
        selectorHostingView?.rootView = SelectorOverlayView(
            title: "",
            subtitle: "",
            systemImage: "",
            confirmed: false
        )
        selectorHostingView?.isHidden = true
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

        let selectorHostingView = NSHostingView(rootView: SelectorOverlayView(
            title: "",
            subtitle: "",
            systemImage: "",
            confirmed: false
        ))
        selectorHostingView.frame = wrapper.bounds
        selectorHostingView.autoresizingMask = [.width, .height]
        selectorHostingView.isHidden = true
        wrapper.addSubview(selectorHostingView)

        let messageHostingView = NSHostingView(rootView: MessageOverlayView(title: "", detail: nil, icon: .info, tint: .white))
        messageHostingView.frame = wrapper.bounds
        messageHostingView.autoresizingMask = [.width, .height]
        messageHostingView.isHidden = true
        wrapper.addSubview(messageHostingView)

        panel.contentView = wrapper
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel = panel
        self.hostingView = hostingView
        self.selectorHostingView = selectorHostingView
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

/// Transient confirmation shown while cycling a selection (style or translation
/// target) with the hotkey. The icon occupies a single slot and morphs into a
/// green checkmark right before the overlay closes. Pure presentation — the
/// timing lives in the panel, which swaps `confirmed` and hides the overlay.
private struct SelectorOverlayView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let confirmed: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Image(systemName: confirmed ? "checkmark.circle.fill" : systemImage)
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

