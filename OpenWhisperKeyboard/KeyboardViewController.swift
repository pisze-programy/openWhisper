import UIKit
import SwiftData
import OpenWhisperShared

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {
    private let headerBar: UIStackView = {
        let titleLabel = UILabel()
        titleLabel.text = "OpenWhisper"
        titleLabel.font = .boldSystemFont(ofSize: 15)
        let hintLabel = UILabel()
        hintLabel.text = "Tap a transcription to insert it"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
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

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[Keyboard] viewDidLoad start")
        setupLayout()
        print("[Keyboard] viewDidLoad end")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[Keyboard] viewDidAppear start, store: \(ModelLocations.historyStoreURL.path)")

        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil else {
            print("[Keyboard] APP GROUP UNAVAILABLE — missing entitlement/provisioning")
            showMessage("App Group unavailable — enable App Groups in Xcode (Signing & Capabilities) and rebuild")
            return
        }

        do {
            container = try ModelContainer(
                for: TranscriptionItem.self,
                configurations: ModelConfiguration(url: ModelLocations.historyStoreURL)
            )
            print("[Keyboard] ModelContainer OK")
        } catch {
            print("[Keyboard] ModelContainer FAILED: \(error)")
            showMessage("Store error: \(error.localizedDescription)")
            return
        }
        UserDefaults(suiteName: AppGroup.identifier)?.set(Date(), forKey: AppGroup.keyboardLastUsedKey)
        loadHistory()
        print("[Keyboard] viewDidAppear end")
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

    private func loadHistory() {
        guard let container else {
            items = []
            updateVisibility()
            return
        }
        do {
            var descriptor = FetchDescriptor<TranscriptionItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 50
            items = try container.mainContext.fetch(descriptor)
            print("[Keyboard] fetch OK, items=\(items.count)")
        } catch {
            print("[Keyboard] fetch FAILED: \(error)")
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
