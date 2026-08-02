import SwiftUI

/// OpenWhisper design tokens — the single source of truth for colors, materials,
/// metrics and typography shared by the app and the keyboard extension.
public enum AppTheme {
    // MARK: Colors
    public static let accent = Color.accentColor
    public static let destructive = Color.red
    public static let secondaryLabel = Color.secondary

    // MARK: Materials / surfaces
    public static let surface = AnyShapeStyle(.ultraThinMaterial)

    // MARK: Metrics
    public static let appRecordButtonSize: CGFloat = 72
    public static let keyboardRecordButtonSize: CGFloat = 88
    public static let cardCornerRadius: CGFloat = 16
    public static let buttonCornerRadius: CGFloat = 12
    public static let smallSpacing: CGFloat = 8
    public static let mediumSpacing: CGFloat = 14
    public static let largeSpacing: CGFloat = 16

    // MARK: Typography
    public static let captionFont = Font.footnote
    public static let hintFont = Font.subheadline
    public static let timerFont = Font.system(.title2, design: .monospaced)
}
