import Foundation

/// Pulls a Parakeet Core ML model from the HuggingFace Hub so callers
/// don't have to stage `.mlpackage` folders by hand.
///
/// Uses HF's REST tree API to discover every file (including nested
/// files inside each `.mlpackage` directory), then fetches them via
/// `URLSession` to a persistent cache under
/// ``defaultCacheDirectory()``. Subsequent calls with the same repo ID
/// detect the existing cached dir and return instantly.
public struct ModelDownloader {

    /// Progress callback: `(bytesDownloaded, totalBytes, fileBeingDownloaded)`.
    /// `totalBytes` is an estimate summed from the HF tree response; may be
    /// slightly off for LFS files but close enough for a progress bar.
    public typealias ProgressHandler = @Sendable (Int64, Int64, String) -> Void

    public var cacheDirectory: URL
    public var session: URLSession
    public var userAgent: String

    public init(
        cacheDirectory: URL? = nil,
        session: URLSession = .shared,
        userAgent: String = "parakeet-coreml-swift/1.0"
    ) {
        self.cacheDirectory = cacheDirectory ?? ModelDownloader.defaultCacheDirectory()
        self.session = session
        self.userAgent = userAgent
    }

    /// Default cache root: `~/Library/Caches/com.parakeet-tdt/hf-models/<repo>/`.
    public static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("com.parakeet-tdt", isDirectory: true)
            .appendingPathComponent("hf-models", isDirectory: true)
    }

    /// Ensure every file in `repoId`'s main branch is present under
    /// `cacheDirectory/<repo-sanitised>/`. Returns that directory.
    ///
    /// `skipIfPresent` returns the existing dir without hitting the
    /// network if it already exists. Set to `false` to force a refresh
    /// (checks file sizes / etags and re-downloads mismatched files).
    public func download(
        repoId: String,
        branch: String = "main",
        skipIfPresent: Bool = true,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        let repoDir = cacheDirectory
            .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "_"))
        let completionMarker = repoDir.appendingPathComponent(".complete")

        if skipIfPresent && FileManager.default.fileExists(atPath: completionMarker.path) {
            return repoDir
        }

        try FileManager.default.createDirectory(
            at: repoDir, withIntermediateDirectories: true
        )

        let files = try await listFiles(repoId: repoId, branch: branch)
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
        var downloaded: Int64 = 0

        for file in files {
            let destination = repoDir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if skipIfPresent {
                // Quick equality check by size. HF files are content-addressed
                // via git-lfs, so a matching size is a strong signal.
                if let attrs = try? FileManager.default.attributesOfItem(
                    atPath: destination.path
                ),
                   let existing = attrs[.size] as? Int64,
                   existing == file.size
                {
                    downloaded += file.size
                    progress?(downloaded, totalBytes, file.path)
                    continue
                }
            }

            try await downloadFile(
                repoId: repoId,
                branch: branch,
                path: file.path,
                destination: destination
            )
            downloaded += file.size
            progress?(downloaded, totalBytes, file.path)
        }

        try Data().write(to: completionMarker)
        return repoDir
    }

    // MARK: - Internals

    struct FileEntry {
        let path: String
        let size: Int64
    }

    /// Recursive file listing for a HF repo. Walks `.mlpackage` directories
    /// manually because the `recursive=true` tree API doesn't exist on every
    /// HF deployment.
    private func listFiles(
        repoId: String,
        branch: String
    ) async throws -> [FileEntry] {
        var out = [FileEntry]()
        try await walk(repoId: repoId, branch: branch, path: "", into: &out)
        return out
    }

    private func walk(
        repoId: String,
        branch: String,
        path: String,
        into out: inout [FileEntry]
    ) async throws {
        let urlStr = "https://huggingface.co/api/models/\(repoId)/tree/\(branch)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ParakeetError.downloadFailed(
                repoId: repoId, reason: "bad URL: \(urlStr)"
            )
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ParakeetError.downloadFailed(
                repoId: repoId,
                reason: "tree API \(url.path) -> HTTP \(code)"
            )
        }
        struct Entry: Decodable {
            let type: String
            let path: String
            let size: Int64
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        for e in entries {
            if e.type == "directory" {
                try await walk(
                    repoId: repoId, branch: branch, path: e.path, into: &out
                )
            } else {
                out.append(FileEntry(path: e.path, size: e.size))
            }
        }
    }

    private func downloadFile(
        repoId: String,
        branch: String,
        path: String,
        destination: URL
    ) async throws {
        let urlStr = "https://huggingface.co/\(repoId)/resolve/\(branch)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ParakeetError.downloadFailed(
                repoId: repoId, reason: "bad URL: \(urlStr)"
            )
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Use download(for:) so large LFS files stream to a temp file rather
        // than through memory.
        let (tmp, response) = try await session.download(for: req)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ParakeetError.downloadFailed(
                repoId: repoId,
                reason: "download \(path) -> HTTP \(code)"
            )
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // moveItem can fail across volumes; fall back to copy.
        do {
            try FileManager.default.moveItem(at: tmp, to: destination)
        } catch {
            try FileManager.default.copyItem(at: tmp, to: destination)
        }
    }
}
