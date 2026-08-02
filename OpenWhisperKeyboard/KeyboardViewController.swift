import UIKit
import SwiftUI
import SwiftData
import OpenWhisperShared

final class KeyboardViewController: UIInputViewController {
    @MainActor private let model = KeyboardDictationModel()

    private var hosting: UIHostingController<KeyboardDictationView>?

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

        view.backgroundColor = .clear

        model.onInsertText = { [weak self] text in
            self?.insertText(text)
        }

        model.onOpenApp = { [weak self] in
            self?.openDictationFallback()
        }

        model.isFullAccessGranted = hasFullAccess

        model.refreshConfiguration()
        installSurface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        configureDictationBehavior()

        model.isFullAccessGranted = hasFullAccess
        model.refreshConfiguration()

        DarwinBridge.post(.keepWarm)
        DarwinBridge.post(.ping)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if model.isRecording || model.isTranscribing {
            model.cancel()
        }
    }

    private func installSurface() {
        guard hosting == nil else { return }
        let root = KeyboardDictationView(
            model: model,
            onOpenSettings: { [weak self] in self?.openKeyboardSettings() },
            onOpenLanguageSettings: { [weak self] in self?.openLanguageSettings() }
        )
        let hosting = UIHostingController(rootView: root)

        hosting.sizingOptions = []
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

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
        let duration = model.elapsed
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

    private func openDictationFallback() {
        openUrls([
            URL(string: "openwhisper://dictate"),
            URL(string: "App-Prefs:root=General&path=Keyboard"),
            URL(string: UIApplication.openSettingsURLString),
        ].compactMap { $0 })
    }

    private func openKeyboardSettings() {
        openUrls([
            URL(string: "openwhisper://settings"),
            URL(string: "App-Prefs:root=General&path=Keyboard"),
            URL(string: UIApplication.openSettingsURLString),
        ].compactMap { $0 })
    }

    private func openLanguageSettings() {
        openUrls([
            URL(string: "openwhisper://settings?section=language"),
            URL(string: "App-Prefs:root=General&path=Keyboard"),
            URL(string: UIApplication.openSettingsURLString),
        ].compactMap { $0 })
    }

    private func openUrls(_ candidates: [URL]) {
        var candidates = candidates
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
