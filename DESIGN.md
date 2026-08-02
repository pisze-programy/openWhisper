# Design System — OpenWhisper

> How we design. Read this instead of browsing every file: it explains what guides
> us, the tokens we use, the shared components, and the rules for creating new views.
> The same look applies to the **app** and the **keyboard extension** — they share one
> design system.

---

## 1. Philosophy

- **Native, minimal, premium.** Standard iOS controls and system styles first;
  custom design only where it adds clarity.
- **Follow Apple's HIG and the Liquid Glass design language** (iOS 26).
- **Glass is for overlay elements, not main content.** Liquid Glass sits *on top* of
  UI (floating buttons, toolbars, the record bar, contextual controls). Applying it to
  list rows or cards makes the UI look busy and un-Apple-like.
- **One design system everywhere.** The app and the keyboard extension share the same
  tokens (`AppTheme`) and components (`MicRecordButton`, `LiveWaveform`,
  `RecordingSurface`). Never restyle the keyboard to look different from the app.
- **Dark mode and Dynamic Type are supported by default** — we use semantic system
  colors (`.primary`, `.secondary`, `.accentColor`), not hardcoded hex.

---

## 2. Apple guidance — summary & links

### Liquid Glass (iOS 26+)

- `glassEffect(_:in:)` — the core modifier, e.g.
  `.glassEffect(.regular.tint(AppTheme.accent.opacity(0.18)).interactive(), in: Circle())`.
- `.tint(...)` colors the glass; `.interactive()` adds press feedback (shimmer + scale).
- `GlassEffectContainer` / `glassEffectUnion` — group nearby glass elements so they
  blend like one drop of liquid.
- `.buttonStyle(.glass)` — a ready glass button style.
- **Rule:** glass only on floating/overlay elements. Don't glass the whole screen.
- **Fallback:** on iOS < 26 use `.ultraThinMaterial` (our shared components handle the
  `#available(iOS 26.0, *)` switch for you).

### Corners, spacing, typography

- **Continuous (squircle) corners**, scaled by role: cards **16 pt**, buttons **12 pt**.
- **8-pt spacing grid** — spacing values live in `AppTheme` (8 / 14 / 16).
- **SF typography**, system weights; monospaced digits for timers.

### Links

- Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Custom Liquid Glass in SwiftUI (practical): https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/
- HIG materials: https://developer.apple.com/design/human-interface-guidelines/materials

---

## 3. Design tokens — `AppTheme`

**File:** `OpenWhisperShared/Sources/OpenWhisperShared/AppTheme.swift` (public, shared by
the app target and the keyboard extension).

**Rule: always use `AppTheme` — never hardcode colors, corner radii, spacing or fonts
in a view.**

| Token | Value | Use for |
|---|---|---|
| `AppTheme.accent` | `Color.accentColor` | Primary accents, icons, selected state |
| `AppTheme.destructive` | `Color.red` | Stop/recording, destructive actions |
| `AppTheme.secondaryLabel` | `Color.secondary` | Hints, captions, secondary text |
| `AppTheme.surface` | `.ultraThinMaterial` | Fallback material (< iOS 26); secondary surfaces |
| `AppTheme.appRecordButtonSize` | 72 | Record button in the app |
| `AppTheme.keyboardRecordButtonSize` | 88 | Record button in the keyboard (it's the primary control) |
| `AppTheme.cardCornerRadius` | 16 | Cards, grouped surfaces |
| `AppTheme.buttonCornerRadius` | 12 | Buttons |
| `AppTheme.smallSpacing` | 8 | Tight spacing |
| `AppTheme.mediumSpacing` | 14 | Standard vertical rhythm |
| `AppTheme.largeSpacing` | 16 | Section spacing |
| `AppTheme.captionFont` | `.footnote` | Captions, hints, error text |
| `AppTheme.hintFont` | `.subheadline` | Secondary headings, status text |
| `AppTheme.timerFont` | `.system(.title2, design: .monospaced)` | Timers / durations |

---

## 4. Shared components

All in `OpenWhisperShared/Sources/OpenWhisperShared/`, `public`, used by both targets.

| Component | What it is | Where used |
|---|---|---|
| `MicRecordButton` | The record button: circular; Liquid Glass (iOS 26) / material fallback when idle, solid red when recording; `mic.fill`/`stop.fill`. | App `HistoryView`, keyboard `RecordingSurface` |
| `LiveWaveform` | Animated waveform bars from live audio samples (uses shared `WaveformBars`). | App `HistoryView`, keyboard `RecordingSurface` |
| `RecordingSurface` | Full dictation surface: idle mic → waveform + timer + stop/cancel → transcribing spinner → error. Value/callback-driven. | Keyboard (hosted via `UIHostingController`) |
| `GlassBackground` / `GlassCard` | Card surface: `glassEffect(.regular)` on iOS 26, `.ultraThinMaterial` fallback. | App cards, list rows, bottom bar |

**Keyboard hosting note:** the keyboard is a `UIInputViewController` that hosts SwiftUI
through a single `UIHostingController` observing a `KeyboardDictationModel`
(`@ObservedObject`). It renders the exact same `RecordingSurface` as the app's UI uses
via the shared components — keep it that way; don't build a second, divergent keyboard UI.

---

## 5. Platform notes

- **iOS 26+:** Liquid Glass is active; shared components use `glassEffect` with a
  material fallback below iOS 26 (handled internally).
- **Keyboard extension:** transparent background so the system keyboard background shows
  through (like the native keyboard). Don't paint an opaque background over it.
- **iPad:** keep content columns capped (see `RecordingSurface`'s `maxWidth: 420`) so the
  layout stays compact on wide screens.

---

## 6. How to create a new view (checklist)

1. **Use `AppTheme` tokens** for every color, corner radius, spacing and font. No
   hardcoded values.
2. **Reuse the shared components** (`MicRecordButton`, `LiveWaveform`,
   `RecordingSurface`, `GlassCard`/`GlassBackground`) whenever the UI matches their role.
3. **Glass only on overlay/floating elements.** If a view is part of the main content
   (rows, cards), keep it on a plain/system background.
4. **Continuous corners + 8-pt spacing grid.**
5. **Semantic system colors** (light/dark aware). No hardcoded hex.
6. **If it goes in both the app and the keyboard, put it in `OpenWhisperShared`** and
   make it `public` — never duplicate UI between targets.

---

## 7. Notes

- The keyboard's language hint, the app's about screen, and all surfaces derive from the
  same tokens — if you change `AppTheme`, everything updates together.
- Fonts use the system dynamic type; don't disable it unless there is a strong reason.
