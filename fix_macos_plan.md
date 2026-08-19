# OpenWhisper macOS — Fix Plan (iteracja 2, po pierwszej instalacji)

Wszystkie błędy zgłoszone po pierwszej próbie uruchomienia `openWhisperMac`. Plan
napraw w kolejności od blokujących do kosmetycznych.

---

## 1. [BLOKER] Wyłącz sandbox — rozwiązuje błędy 1, 5, 12 i model download

**Objawy:**
- "openWhisperMac would like to access data from other apps" (automation.apple-events)
- Aplikacja nie pojawia się na liście Accessibility w Privacy
- FluidAudio nie znajduje modelu: `Models not found in cache at .../Containers/pl.piszeprogramy.openWhisper.mac/...`
  → sandbox daje osobny kontener, nie widać globalnego `~/Library/Application Support/FluidAudio/`
- `CFPrefsPlistSource` warnings (sandbox + App Group)

**Decyzja:** aplikacja bez App Store (jak wzorce) → **wyłączamy sandbox**.
- `openWhisperMac/Info.entitlements`: `com.apple.security.app-sandbox` → `false`
- Usunąć `com.apple.security.automation.apple-events` (nie używamy Apple Events —
  wklejanie idzie przez Accessibility + CGEvent). To kasuje dialog "access data from other apps".
- Zostawić: `application-groups`, `network.client`, `device.audio-input`.

**Skutek:** model FluidAudio widzi globalny katalog (już pobrany, 461 MB), brak
powtórnego downloadu, brak dialogu dostępu, aplikacja widoczna dla Accessibility.

---

## 2. [BLOKER] Napraw flow onboardingu — rozwiązuje 3, 4, 8, 9

**Objawy:**
- "Complete setup to begin" zamiast Setup Window
- Onboarding nie na wierzchu, brak w CMD-TAB (LSUIElement)
- Microphone Grant nie aktualizuje statusu po dialogu
- Settings otwiera "Complete setup to begin"

**Fiksy:**

### 2a. AppDelegate — auto-otwarcie Setup + activation policy
- W `applicationDidFinishLaunching`:
  - jeśli `!settings.onboardingCompleted` → `NSApp.setActivationPolicy(.regular)`
    i otwórz Setup Window przez `openWindow(id: "setup")`.
  - jeśli ukończony → zostaw `.accessory`.
- Obserwować `settings.onboardingCompleted`; po `true` → zamknij Setup i wróć do `.accessory`.

### 2b. `MacRootView` — usuń ekran "Complete setup to begin"
- Nie pokazuj go. Gdy `!onboardingCompleted` → pokaż pusty widok
  (`Color.clear` / `ProgressView`), bo Setup i tak jest otwarty.
- Gdy ukończony → sidebar History · Settings.

### 2c. `PermissionManager` → `@Observable` + refresh po grant
- Zmienić na `@MainActor @Observable final class` (jak inne serwisy).
- `requestMicrophone()` po `requestAccess` robi `refresh()` (już robi) — ale UI musi
  obserwować zmiany: `PermissionRow` czyta `PermissionManager.shared.microphoneStatus`
  przez `@Environment` lub `@State` odświeżane w `.task`/`.onChange`.
- `PermissionRow`: użyć `@State` z refresh-em po akcji (albo environment inject).

### 2d. Menu bar — Settings niezależne od onboardingu
- "Show OpenWhisper" w menu bar: jeśli `!onboardingCompleted` → otwórz Setup;
  jeśli ukończony → otwórz główne okno.
- Po onboardingu okno główne pokazuje sidebar, więc Settings jest osiągalne.

---

## 3. [BLOKER] Napraw overlay — rozwiązuje 6, 10, 11

**Objawy:**
- Overlay pokazuje tylko ikonę appki, wygląda tragicznie
- Jest ucięty pod dolną krawędzią ekranu
- Po nagraniu zostaje widoczny na czerwono

**Fiksy (`StatusOverlayPanel.swift` + `StatusOverlayView.swift`):**

### 3a. Pozycja — ponad Dockiem
- `y = screen.visibleFrame.minY + 80` zamiast `+ 24`.
- Używać `screen.visibleFrame` (już jest) — `minY + 80` stawia pill nad Dockiem.

### 3b. Wygląd — glass per DESIGN.md
- `StatusOverlayView`: kapsułka z `.glassEffect(.regular.tint(...))` na macOS 26
  (`#available(iOS 26.0, macOS 26.0, *)`), fallback `.ultraThinMaterial`.
- Ikona: konkretny status (mic/arrow/check/error), nie `waveform` dla wszystkiego.
- Tekst statusu + ikona razem.

### 3c. Animacja wejścia/wyjścia (bubble in/out)
- Wejście: `NSAnimationContext.runAnimationGroup` — alpha 0→1 + scale 0.8→1.
- Wyjście: alpha→0 + scale→0.8, potem `orderOut`.
- Zamiast nagłego `orderOut`/`orderFront`.

### 3d. Chowanie po nagraniu
- `DictationOrchestrator.setPhase(.done)` → po 1.5 s przejście na `.idle`.
- `setPhase(.failed)` → pokaż 3 s, potem `.idle` + `ducking.restore()` + `sounds.play(.error)`.
- Gdy `decision` = discard → ukryj overlay (nie zostaje na czerwono).

---

## 4. [BLOKER] Mikrofon — pytaj tylko raz — rozwiązuje 7

**Objawy:** po nadaniu uprawnienia w Onboardingu, hotkey i tak pyta ponownie.

**Fix (`MacRecorder.start()`):**
- Zamiast zawsze `requestAccess`, sprawdź status:
  - `.authorized` → nie pytaj.
  - `.notDetermined` → `requestAccess`.
  - `.denied`/`.restricted` → rzuć `RecorderError.permissionDenied`.
- Onboarding robi `requestAccess` → ustawia `.authorized` → hotkey już nie pyta.

---

## 5. [WAŻNE] Podłącz AudioEngineRecovery — rozwiązuje `throwing -10877`

**Objawy:** `throwing -10877` (kAudioUnitErr) przy starcie/restarcie silnika.

**Fix:**
- Dodać do `MacRecorder` obserwator `AVAudioEngineConfigurationChange`
  (debounce 0.15 s, quiescence 1 s, burst limit 4/5 s, podmiana silnika bez utraty bufora).
- Reuse wzorca recovery (mamy `RecoveryAudioStore`; dodać `AudioEngineRecoveryCoordinator`).

---

## 6. [KOSMETYCZNE] Xcode: layout recursion

**Objawy:** `_NSDetectedLayoutRecursion` z `NSHostingView` w overlay.

**Fix:** W `StatusOverlayPanel` nie używać `contentView?.fittingSize` ręcznie;
ustawić `hostingView.sizingOptions` i `panel.contentView = hostingView`, a rozmiar
liczyć z `fittingSize` **raz** przy tworzeniu. Unikać `-layoutSubtreeIfNeeded` w pętli.

---

## 7. [KOSMETYCZNE] iOS warnings

- `CFPrefsPlistSource` (sandbox + App Group): nieszkodliwe, bez zmian (iOS zostaje
  sandboxowany — App Store).
- `System gesture gate timed out` / `UIContextMenuInteraction`: znane ostrzeżenia
  systemowe, bez zmian.

---

## 8. [WERYFIKACJA] "Failed to open document OpenRouterFormattingClient.swift"

- Błąd workspace, nie runtime: plik przeniesiony przez `git mv`. Fix: clean
  DerivedData, zamknąć/otworzyć Xcode, `xcodebuild -resolvePackageDependencies`.

---

## Kolejność wdrożenia

1. Entitlements: sandbox off + usuń automation.apple-events (1).
2. Flow onboardingu: AppDelegate + MacRootView + PermissionManager @Observable + menu bar (2).
3. Overlay: pozycja + glass + animacja + chowanie (3).
4. Mikrofon pytaj raz (4).
5. AudioEngineRecovery (5).
6. Layout recursion (6).
7. Weryfikacja: build Mac + iOS, smoke test onboardingu, nagrania, overlay.

---

## Kryterium akceptacji (smoke test)

- Start: Setup window na wierzchu, widoczny w CMD-TAB, bez dialogu "access data".
- Microphone Grant → status zmienia się natychmiast, bez ponownego pytania przy hotkey.
- Accessibility → aplikacja jest na liście Privacy (sandbox off).
- Hotkey right ⌘+⌥ → glass overlay "Listening" nad Dockiem; release → transcribing;
  koniec → overlay znika; text w schowku.
- Brak "Complete setup to begin" w oknie głównym.
- Settings osiągalne z menu bar i sidebar.
