import ArgumentParser
import Foundation
import ParakeetTDT

@main
struct Parakeet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parakeet",
        abstract: "Transcribe audio with Parakeet TDT on Core ML.",
        subcommands: [Transcribe.self, DownloadModels.self],
        defaultSubcommand: Transcribe.self
    )
}

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file."
    )

    @Argument(
        help: "Path to audio file (wav / flac / mp3 / m4a / ...). Mono-downmixed and resampled to 16 kHz automatically."
    )
    var audio: String

    @Option(
        name: [.short, .customLong("models")],
        help: "Directory containing encoder.mlpackage, decoder.mlpackage, joint.mlpackage, tokenizer.json. If omitted, models are auto-downloaded from --hf-repo."
    )
    var models: String? = nil

    @Option(
        name: .customLong("hf-repo"),
        help: "HuggingFace repo to download models from when --models is not set. Default: \(ParakeetTranscriber.defaultRepoId)."
    )
    var hfRepo: String = ParakeetTranscriber.defaultRepoId

    @Option(
        name: .customLong("compute-units"),
        help: "Core ML scheduler target: ane (Neural Engine + CPU), gpu (GPU + CPU), cpu (CPU only), all. Default: ane."
    )
    var computeUnits: String = "ane"

    @Flag(
        name: .customLong("delete-source-after-compile"),
        help: "Delete the source .mlpackage after successful compile. Halves peak disk usage at the cost of having to re-download if you clear the cache."
    )
    var deleteSourceAfterCompile: Bool = false

    @Flag(
        name: .customLong("show-timing"),
        help: "Print detailed timing breakdown after the transcript."
    )
    var showTiming: Bool = false

    @Option(
        name: .customLong("max-seconds"),
        help: "Cap audio length. Default: full file."
    )
    var maxSeconds: Double? = nil

    @Option(
        name: .customLong("decoder-workers"),
        help: "Parallel decode-loop workers. Default: 4 for GPU / all, 2 for ANE, 1 for CPU (avoids CPU core contention with the on-CPU encoder)."
    )
    var decoderWorkers: Int? = nil

    func validate() throws {
        guard ["ane", "gpu", "cpu", "all"].contains(computeUnits) else {
            throw ValidationError(
                "compute-units must be one of: ane, gpu, cpu, all (got \(computeUnits))"
            )
        }
    }

    func run() async throws {
        let units: ParakeetComputeUnits = {
            switch computeUnits {
            case "gpu": return .gpu
            case "cpu": return .cpu
            case "all": return .all
            default:    return .ane
            }
        }()

        var err = StderrStream()

        let transcriber: ParakeetTranscriber
        let loadStart = Date()
        if let localModels = models, !localModels.isEmpty {
            let modelsURL = URL(fileURLWithPath: localModels, isDirectory: true)
            print("Loading models from \(modelsURL.path) (compute: \(computeUnits))...", to: &err)
            transcriber = try ParakeetTranscriber(
                modelsRoot: modelsURL,
                computeUnits: units,
                deleteSourceAfterCompile: deleteSourceAfterCompile,
                decoderWorkers: decoderWorkers
            )
        } else {
            print("Fetching models from HuggingFace (\(hfRepo)) -- first launch only...", to: &err)
            transcriber = try await ParakeetTranscriber.fromHuggingFace(
                repoId: hfRepo,
                computeUnits: units,
                decoderWorkers: decoderWorkers,
                progress: { done, total, name in
                    let pct = total > 0 ? (Double(done) / Double(total) * 100.0) : 0
                    let name40 = String(name.prefix(40))
                    print(
                        String(
                            format: "  \r[%5.1f%%] %@",
                            pct, name40 as CVarArg
                        ),
                        to: &err
                    )
                }
            )
        }
        let loadSecs = Date().timeIntervalSince(loadStart)
        print("Models ready in \(String(format: "%.2f", loadSecs)) s", to: &err)

        let audioURL = URL(fileURLWithPath: audio)
        let samples: [Float]
        if let cap = maxSeconds {
            let raw = try AudioLoader.loadMono16k(at: audioURL)
            let capCount = min(raw.count, Int(cap * Double(transcriber.sampleRate)))
            samples = Array(raw[0..<capCount])
        } else {
            samples = try AudioLoader.loadMono16k(at: audioURL)
        }
        let seconds = Double(samples.count) / Double(transcriber.sampleRate)
        print(
            "Transcribing \(String(format: "%.2f", seconds)) s of audio...",
            to: &err
        )

        let result = try transcriber.transcribe(samples: samples)

        print(result.text)

        if showTiming {
            let t = result.timing
            print(
                """

                ----- timing -----
                audio:      \(String(format: "%7.3f", result.audioDurationSeconds)) s
                inference:  \(String(format: "%7.3f", result.inferenceDurationSeconds)) s
                  mel:      \(String(format: "%7.3f", t.melExtract)) s
                  encoder:  \(String(format: "%7.3f", t.encoder)) s
                  decode:   \(String(format: "%7.3f", t.decoderLoop)) s   (decoder + joint loop)
                  detok:    \(String(format: "%7.3f", t.detokenize)) s
                RTFx:       \(String(format: "%7.2fx", result.rtfx))
                tokens:     \(result.tokenIds.count)
                """,
                to: &err
            )
        }
    }
}

struct DownloadModels: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Pre-download the Core ML model bundle from HuggingFace into the local cache. Useful for staging a build or running offline later."
    )

    @Option(
        name: .customLong("hf-repo"),
        help: "HuggingFace repo to download."
    )
    var hfRepo: String = ParakeetTranscriber.defaultRepoId

    func run() async throws {
        var err = StderrStream()
        print("Downloading \(hfRepo) ...", to: &err)
        let downloader = ModelDownloader()
        let dir = try await downloader.download(
            repoId: hfRepo,
            progress: { done, total, name in
                let pct = total > 0 ? (Double(done) / Double(total) * 100.0) : 0
                let name40 = String(name.prefix(40))
                print(
                    String(format: "  [%5.1f%%] %@", pct, name40 as CVarArg),
                    to: &err
                )
            }
        )
        print("Models at: \(dir.path)", to: &err)
        print(dir.path)  // stdout: the path, so callers can script around it
    }
}

/// Lightweight stderr writer so we can redirect status messages away from
/// stdout (which carries the transcript).
private struct StderrStream: TextOutputStream {
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
