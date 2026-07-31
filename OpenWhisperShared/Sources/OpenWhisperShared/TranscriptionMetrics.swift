import Darwin
import Foundation
import os
import ParakeetTDT

/// Lightweight performance instrumentation for the transcription path.
///
/// Dependency-free helpers: a wall-clock + memory + CPU snapshot taken around
/// an operation and a one-line `os.Logger` report. No UI, no persistence.
public enum TranscriptionMetrics {
    public static let logger = Logger(
        subsystem: "com.piszeprogramy.openWhisper",
        category: "transcription"
    )

    /// A point-in-time snapshot of this process.
    public struct Snapshot {
        public let wall: Double
        public let footprintMB: Double
        public let availableMB: Double
        public let processCPUSeconds: Double

        public static func capture() -> Snapshot {
            Snapshot(
                wall: Date().timeIntervalSinceReferenceDate,
                footprintMB: Self.footprintMB(),
                availableMB: Self.availableMB(),
                processCPUSeconds: Self.processCPUSeconds()
            )
        }

        /// App memory footprint (`phys_footprint`), in MiB.
        private static func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
            )
            let kr = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
                }
            }
            guard kr == KERN_SUCCESS else { return 0 }
            return Double(info.phys_footprint) / (1024 * 1024)
        }

        /// Memory the process could still allocate before jetsam, in MiB.
        private static func availableMB() -> Double {
            #if os(iOS)
            return Double(os_proc_available_memory()) / (1024 * 1024)
            #else
            return 0
            #endif
        }

        /// Cumulative user + system CPU time used by this process, in seconds.
        private static func processCPUSeconds() -> Double {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
            let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
            return user + system
        }
    }

    /// Log a one-line report of everything that changed since `start`.
    public static func report(
        _ event: String,
        since start: Snapshot,
        extra: String = ""
    ) {
        let end = Snapshot.capture()
        let wallMS = (end.wall - start.wall) * 1000
        let cpuMS = (end.processCPUSeconds - start.processCPUSeconds) * 1000
        let cpuPct = wallMS > 0 ? Int((cpuMS / wallMS * 100).rounded()) : 0
        let suffix = extra.isEmpty ? "" : " | \(extra)"
        logger.info(
            "\(event, privacy: .public): wall \(fmt(wallMS)) ms | cpu \(fmt(cpuMS)) ms (\(cpuPct)%) | footprint \(fmt(start.footprintMB)) -> \(fmt(end.footprintMB)) MB (Δ \(fmt(end.footprintMB - start.footprintMB))) | avail \(fmt(end.availableMB)) MB\(suffix)"
        )
    }

    /// Renders the per-stage STT breakdown from a `Transcription`.
    public static func timingLine(_ t: Transcription) -> String {
        let t2 = t.timing
        return [
            "inference \(fmt(t.inferenceDurationSeconds * 1000)) ms",
            "mel \(fmt(t2.melExtract * 1000)) ms",
            "encoder \(fmt(t2.encoder * 1000)) ms",
            "decode \(fmt(t2.decoderLoop * 1000)) ms",
            "detok \(fmt(t2.detokenize * 1000)) ms",
            "audio \(fmt(t.audioDurationSeconds)) s",
            "rtfx \(fmt(t.rtfx))x",
        ].joined(separator: " | ")
    }

    private static func fmt(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
