import CoreML
import CryptoKit
import Foundation

/// Compiles `.mlpackage` directories into `.mlmodelc` bundles once and caches
/// them inside the app's Caches directory. Subsequent loads skip the compile.
///
/// Compiling an `.mlpackage` is relatively expensive (single-digit seconds for
/// the Parakeet encoder on M-class silicon) and the result is keyed on the
/// package's on-disk contents, so we can safely reuse a compiled bundle as
/// long as the source `.mlpackage` hasn't changed.
///
/// Optionally, once compilation succeeds the source `.mlpackage` can be
/// deleted in place via ``deleteSourceAfterCompile``: useful for
/// disk-constrained deployment where the download + compile + discard-source
/// flow halves peak disk usage.
public struct ModelCache {
    public var cacheDirectory: URL
    public var deleteSourceAfterCompile: Bool

    public init(
        cacheDirectory: URL? = nil,
        deleteSourceAfterCompile: Bool = false
    ) {
        self.cacheDirectory = cacheDirectory ?? ModelCache.defaultCacheDirectory()
        self.deleteSourceAfterCompile = deleteSourceAfterCompile
    }

    /// Default cache root: `~/Library/Caches/com.parakeet-tdt/mlmodelc`.
    public static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("com.parakeet-tdt", isDirectory: true)
            .appendingPathComponent("mlmodelc", isDirectory: true)
    }

    /// Return the compiled `.mlmodelc` URL for `source`, compiling if needed.
    ///
    /// The returned URL is stable across runs as long as the source contents
    /// don't change, so downstream code can safely hang on to it.
    public func compiledURL(for source: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ParakeetError.modelNotFound(url: source)
        }

        // If the source is already a compiled .mlmodelc there's nothing to do.
        if source.pathExtension == "mlmodelc" {
            return source
        }

        let key = try cacheKey(for: source)
        let target = cacheDirectory
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(
                source.lastPathComponent.replacingOccurrences(
                    of: ".mlpackage", with: ".mlmodelc"
                ),
                isDirectory: true
            )
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // `MLModel.compileModel(at:)` writes into a process-scoped temp dir;
        // we move it under our cache so it survives the next launch.
        let tmpCompiled: URL
        do {
            tmpCompiled = try MLModel.compileModel(at: source)
        } catch {
            throw ParakeetError.modelCompileFailed(url: source, underlying: error)
        }

        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        do {
            try FileManager.default.moveItem(at: tmpCompiled, to: target)
        } catch {
            // moveItem can fail across volumes; fall back to copy + cleanup.
            try FileManager.default.copyItem(at: tmpCompiled, to: target)
            try? FileManager.default.removeItem(at: tmpCompiled)
        }

        if deleteSourceAfterCompile {
            try? FileManager.default.removeItem(at: source)
        }
        return target
    }

    /// Content-addressed cache key. Uses file size + mtime for directories
    /// (full SHA256 over every file would be correct but slow for a 650 MB
    /// `.mlpackage`; size + mtime is sufficient to catch intentional edits
    /// because we recompile whenever the HF download is refreshed).
    private func cacheKey(for source: URL) throws -> String {
        var hasher = SHA256()
        hasher.update(data: Data(source.resolvingSymlinksInPath().path.utf8))

        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if let vals = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ) {
                    hasher.update(data: Data(url.lastPathComponent.utf8))
                    if let size = vals.fileSize {
                        withUnsafeBytes(of: Int64(size)) { hasher.update(data: Data($0)) }
                    }
                    if let mtime = vals.contentModificationDate {
                        withUnsafeBytes(of: mtime.timeIntervalSince1970) {
                            hasher.update(data: Data($0))
                        }
                    }
                }
            }
        }
        let digest = hasher.finalize()
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
