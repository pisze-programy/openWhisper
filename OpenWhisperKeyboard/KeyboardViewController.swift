import UIKit
import SwiftUI
import Combine
import os
import SwiftData
import OpenWhisperShared

final class KeyboardViewController: UIInputViewController {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper", category: "keyboard")

    @MainActor private let model = KeyboardDictationModel()

    private var hosting: UIHostingController<RecordingSurface>?
    private var cancellables = Set<AnyCancellable>()

    /// UIKit queries this when deciding dictation support for the keyboard.
    /// Returning nil (the default) makes TextInput's
    /// `TIGetDefaultDictationLanguagesForKeyboardLanguage` crash the host app /
    /// SpringBoard with "key cannot be nil" on iOS 26.x — so always return a
    /// valid identifier, honoring the language picked in the OpenWhisper app.
    override var primaryLanguage: String? {
        get {
            let code = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.languageCodeKey)
            return Self.languageIdentifier(for: code)
        }
        set {}
    }

    private static func languageIdentifier(for code: String?) -> String {
        switch code {
        case "en": return "en-US"
        case "pl": return "pl-PL"
        default: return "en-US"
        }
    }

    // The system injects its own dictation (mic) button when it believes the
    // keyboard relies on system dictation. Advertising our own dictation
    // support (hasDictationKey = true) makes iOS keep its mic out — but the
    // flag must be set in the initializer, not just viewDidLoad (per verified
    // community findings for iOS 16+).
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureDictationBehavior()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDictationBehavior()
    }

    private func configureDictationBehavior() {
        hasDictationKey = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDictationBehavior()
        // Transparent root so the system keyboard background shows through —
        // UIHostingController's view is opaque/black by default otherwise.
        view.backgroundColor = .clear

        // Insert the transcribed text back into the host document, honoring
        // the shared auto-copy / save-to-history settings.
        model.onInsertText = { [weak self] text in
            self?.insertText(text)
        }

        // RecordingSurface captures the @Published values at construction, so
        // rebuild the root view whenever the model changes.
        model.objectWillChange
            .sink { [weak self] _ in self?.installSurface() }
            .store(in: &cancellables)

        installSurface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The system re-evaluates the dictation key each time the keyboard is
        // presented, so (re)apply it here as well.
        configureDictationBehavior()
    }

    private func installSurface() {
        let surface = RecordingSurface(
            isRecording: model.isRecording,
            isTranscribing: model.isTranscribing,
            error: model.error,
            elapsed: model.elapsed,
            getSamples: { [weak model] in model?.liveSamples ?? [] },
            onMicTap: { [weak model] in model?.start() },
            onStop: { [weak model] in model?.stop() },
            onCancel: { [weak model] in model?.cancel() }
        )
        let hosting = UIHostingController(rootView: surface)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        // Default hosting view background is opaque black — make it clear so
        // the system keyboard background (like the native keyboard) shows.
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false

        if let old = self.hosting {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.hosting = hosting
    }

    private func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        if UserDefaults(suiteName: AppGroup.identifier)?.object(forKey: "settings.autoCopy") as? Bool ?? true {
            UIPasteboard.general.string = text
        }
        saveToHistory(text)
    }

    private func saveToHistory(_ text: String) {
        let storeURL = ModelLocations.historyStoreURL
        let duration = model.controller.elapsed
        Task.detached(priority: .utility) {
            guard let container = try? ModelContainer(
                for: TranscriptionItem.self,
                configurations: ModelConfiguration(url: storeURL)
            ) else { return }
            let context = ModelContext(container)
            let item = TranscriptionItem(text: text, duration: duration, source: "keyboard")
            context.insert(item)
            try? context.save()
        }
    }
}
