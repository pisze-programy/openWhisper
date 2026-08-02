import UIKit
import SwiftUI
import SwiftData
import OpenWhisperShared

final class KeyboardViewController: UIInputViewController {
    @MainActor private let model = KeyboardDictationModel()

    private var hosting: UIHostingController<KeyboardDictationView>?

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

        model.isFullAccessGranted = hasFullAccess
        installSurface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The system re-evaluates the dictation key each time the keyboard is
        // presented, so (re)apply it here as well.
        configureDictationBehavior()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The keyboard is going away (dismissed / host backgrounded / switched):
        // stop and transcribe whatever was captured instead of losing it.
        if model.isRecording {
            model.stop()
        }
    }

    private func installSurface() {
        guard hosting == nil else { return }
        let root = KeyboardDictationView(model: model) { [weak self] in
            self?.openKeyboardSettings()
        }
        let hosting = UIHostingController(rootView: root)
        // CRITICAL: default sizingOptions = .intrinsicContentSize makes the system
        // shrink the keyboard to the SwiftUI content's intrinsic size (~116 pt here)
        // and first lays it out at the full screen height — that's the "half
        // screen" + "button flies out" bug. Fill the system keyboard frame instead.
        hosting.sizingOptions = []
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        // Default hosting view background is opaque black — make it clear so
        // the system keyboard background (like the native keyboard) shows.
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false
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
        let chunkSize = 200
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            textDocumentProxy.insertText(String(text[index..<end]))
            index = end
        }
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

    /// "Open Settings": prefers opening the OpenWhisper app at its Settings
    /// screen (where the full-access guidance lives and its link works), and
    /// only falls back to the phone's keyboard settings deep link (then the app
    /// settings pane) if the previous attempt failed.
    private func openKeyboardSettings() {
        var candidates = [
            URL(string: "openwhisper://settings"),
            URL(string: "App-Prefs:root=General&path=Keyboard"),
            URL(string: UIApplication.openSettingsURLString),
        ].compactMap { $0 }

        func tryNext() {
            guard !candidates.isEmpty else { return }
            let url = candidates.removeFirst()
            extensionContext?.open(url) { ok in
                if !ok { tryNext() }
            }
        }
        tryNext()
    }
}
