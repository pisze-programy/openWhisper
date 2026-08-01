import UIKit
import SwiftData
import os
import OpenWhisperShared

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {
    private let languageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var headerBar: UIStackView = {
        let titleLabel = UILabel()
        titleLabel.text = "OpenWhisper"
        titleLabel.font = .boldSystemFont(ofSize: 15)
        let hintLabel = UILabel()
        hintLabel.text = "Tap a transcription to insert it"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel, languageLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No transcriptions yet — dictate in OpenWhisper first"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var container: ModelContainer?
    private var items: [TranscriptionItem] = []
    private var isHistoryLoading = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper", category: "keyboard")

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
        setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The system re-evaluates the dictation key each time the keyboard is
        // presented, so (re)apply it here as well.
        configureDictationBehavior()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UserDefaults(suiteName: AppGroup.identifier)?.set(Date(), forKey: AppGroup.keyboardLastUsedKey)
        loadHistory()
        updateLanguageLabel()
    }

    private func showMessage(_ message: String) {
        items = []
        emptyLabel.text = message
        updateVisibility()
    }

    private func setupLayout() {
        view.addSubview(headerBar)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func updateLanguageLabel() {
        let code = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.languageCodeKey)
        let name = Language.language(for: code)?.name ?? "Auto"
        languageLabel.text = "using \(name) · change in OpenWhisper → Settings"
    }

    private func loadHistory() {
        guard !isHistoryLoading, container == nil else { return }
        isHistoryLoading = true
        let storeURL = ModelLocations.historyStoreURL
        logger.info("Loading history from \(storeURL.path)")
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // SwiftData containers are safe to construct off the main thread;
            // only mainContext usage happens back on the main actor.
            let container = try? ModelContainer(
                for: TranscriptionItem.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            await MainActor.run {
                self.finishLoading(container: container)
            }
        }
    }

    private func finishLoading(container: ModelContainer?) {
        isHistoryLoading = false
        guard let container else {
            logger.error("SwiftData container unavailable — showing empty state")
            showMessage("History unavailable right now")
            return
        }
        self.container = container
        do {
            var descriptor = FetchDescriptor<TranscriptionItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 50
            items = try container.mainContext.fetch(descriptor)
        } catch {
            logger.error("History fetch failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
        updateVisibility()
    }

    private func updateVisibility() {
        tableView.isHidden = items.isEmpty
        emptyLabel.isHidden = !items.isEmpty
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.numberOfLines = 3
        cell.textLabel?.text = items[indexPath.row].text
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < items.count else { return }
        textDocumentProxy.insertText(items[indexPath.row].text)
    }
}
