import Accelerate
import Foundation

/// Log-mel features that match HF's ``ParakeetFeatureExtractor`` numerically.
///
/// Pipeline (mirrors the Python code in
/// ``transformers/models/parakeet/feature_extraction_parakeet.py``):
///   1. Preemphasis: ``y[n] = x[n] - 0.97 * x[n-1]`` (``y[0] = x[0]``).
///   2. STFT: ``n_fft=512``, ``win_length=400``, ``hop_length=160``,
///      non-periodic Hann window, ``pad_mode="constant"`` (PyTorch
///      ``torch.stft`` default, i.e. reflective padding disabled -- frames
///      are centred on the sample with zero-padding).
///   3. ``|STFT|^2`` via ``sqrt(real^2 + imag^2)`` then squaring (matches the
///      HF implementation's two-step form, which keeps round-off identical).
///   4. Slaney-normalised mel filter bank with ``n_mels=128``, ``f_min=0``,
///      ``f_max=sr/2``.
///   5. ``log(mel + 2^-24)``.
///   6. Per-mel-bin normalisation over the (valid, i.e. pre-pad) time axis.
///
/// Implemented with `Accelerate.Framework`'s `vDSP` for the FFT + windowing
/// + matmul-style mel projection.
public final class MelFeatureExtractor {
    public let sampleRate: Int
    public let hopLength: Int
    public let winLength: Int
    public let nFFT: Int
    public let numMelFilters: Int
    public let preemphasis: Float
    public let logGuard: Float
    public let epsilon: Float

    private let hannWindow: [Float]
    private let melRows: [[Float]]
    private let numFreqBins: Int

    // vDSP FFT setup for `n_fft` (real-to-real packed).
    private let fftSetup: vDSP_DFT_Setup

    public init(
        sampleRate: Int = 16_000,
        hopLength: Int = 160,
        winLength: Int = 400,
        nFFT: Int = 512,
        numMelFilters: Int = 128,
        preemphasis: Float = 0.97,
        logGuard: Float = Float(pow(2.0, -24.0)),
        epsilon: Float = 1e-5
    ) throws {
        self.sampleRate = sampleRate
        self.hopLength = hopLength
        self.winLength = winLength
        self.nFFT = nFFT
        self.numMelFilters = numMelFilters
        self.preemphasis = preemphasis
        self.logGuard = logGuard
        self.epsilon = epsilon

        // torch.hann_window(winLength, periodic=false): length = winLength,
        // symmetric end-points. `0.5 - 0.5 * cos(2*pi*n / (N-1))`.
        var window = [Float](repeating: 0, count: winLength)
        let N = Float(winLength - 1)
        for n in 0..<winLength {
            window[n] = 0.5 - 0.5 * cos(2.0 * .pi * Float(n) / N)
        }
        self.hannWindow = window

        let (rows, bins) = MelFilterBank.build(
            sampleRate: Double(sampleRate),
            nFFT: nFFT,
            numMelFilters: numMelFilters
        )
        self.melRows = rows
        self.numFreqBins = bins

        guard let setup = vDSP_DFT_zrop_CreateSetup(
            nil, vDSP_Length(nFFT), .FORWARD
        ) else {
            throw ParakeetError.fftSetupFailed
        }
        self.fftSetup = setup
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }

    /// Output layout: ``(time, mel)`` matching ``ParakeetEncoderWrapper``'s
    /// ``(B, T, n_mels)`` input. The returned ``attention_mask`` is one
    /// `Int32` per output frame (1 = valid, 0 = pad). For a standalone audio
    /// file there's no padding, but we still return a mask so downstream
    /// callers don't need a special case.
    public struct Features {
        public let mel: [[Float]]          // [time][mel]
        public let attentionMask: [Int32]  // [time]
        public var numFrames: Int { mel.count }
    }

    public func extract(from waveform: [Float]) -> Features {
        precondition(waveform.count > 0, "waveform must be non-empty")

        // --- Step 1: preemphasis ---
        var preemph = [Float](repeating: 0, count: waveform.count)
        preemph[0] = waveform[0]
        for n in 1..<waveform.count {
            preemph[n] = waveform[n] - preemphasis * waveform[n - 1]
        }

        // --- Step 2: center-pad for `torch.stft` center=True, pad="constant" ---
        let padLeft = nFFT / 2
        let padRight = nFFT / 2
        var padded = [Float](repeating: 0, count: padLeft + preemph.count + padRight)
        _ = padded.withUnsafeMutableBufferPointer { buf in
            preemph.withUnsafeBufferPointer { src in
                memcpy(
                    buf.baseAddress!.advanced(by: padLeft),
                    src.baseAddress!,
                    preemph.count * MemoryLayout<Float>.size
                )
            }
        }

        // Number of STFT frames, matching torch.stft w/ center=True.
        let numFrames = (padded.count - nFFT) / hopLength + 1
        if numFrames <= 0 {
            return Features(mel: [], attentionMask: [])
        }

        // Working buffers reused across frames.
        var frameBuf = [Float](repeating: 0, count: nFFT)
        var realIn = [Float](repeating: 0, count: nFFT / 2)
        var imagIn = [Float](repeating: 0, count: nFFT / 2)
        var realOut = [Float](repeating: 0, count: nFFT / 2)
        var imagOut = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: numFreqBins)
        var logMelFrames = [[Float]](
            repeating: [Float](repeating: 0, count: numMelFilters),
            count: numFrames
        )

        let padOffset = (nFFT - winLength) / 2

        for t in 0..<numFrames {
            // Zero out the FFT input buffer.
            vDSP_vclr(&frameBuf, 1, vDSP_Length(nFFT))

            // Place the windowed `winLength` samples into the centre of the
            // `nFFT` buffer -- zero-padding on either side.
            let start = t * hopLength
            padded.withUnsafeBufferPointer { paddedPtr in
                let src = paddedPtr.baseAddress!.advanced(by: start)
                hannWindow.withUnsafeBufferPointer { wPtr in
                    frameBuf.withUnsafeMutableBufferPointer { dstBuf in
                        vDSP_vmul(
                            src, 1, wPtr.baseAddress!, 1,
                            dstBuf.baseAddress!.advanced(by: padOffset), 1,
                            vDSP_Length(winLength)
                        )
                    }
                }
            }

            // Pack interleaved real samples into even/odd for real-to-complex
            // packed DFT: vDSP_DFT_zrop splits the input between realIn and
            // imagIn (evens / odds).
            frameBuf.withUnsafeBufferPointer { fBuf in
                realIn.withUnsafeMutableBufferPointer { rBuf in
                    imagIn.withUnsafeMutableBufferPointer { iBuf in
                        let halfN = nFFT / 2
                        for k in 0..<halfN {
                            rBuf[k] = fBuf[2 * k]
                            iBuf[k] = fBuf[2 * k + 1]
                        }
                    }
                }
            }

            vDSP_DFT_Execute(
                fftSetup,
                realIn, imagIn,
                &realOut, &imagOut
            )

            // Unpack into the usual n/2 + 1 real spectrum. vDSP packs DC in
            // realOut[0] and Nyquist in imagOut[0]; we reconstruct the full
            // one-sided spectrum to match torch.stft.
            var real = [Float](repeating: 0, count: numFreqBins)
            var imag = [Float](repeating: 0, count: numFreqBins)
            real[0] = realOut[0] * 0.5       // vDSP scales DC / Nyquist by 2;
            real[numFreqBins - 1] = imagOut[0] * 0.5  // undo.
            for k in 1..<(nFFT / 2) {
                real[k] = realOut[k] * 0.5
                imag[k] = imagOut[k] * 0.5
            }

            // Power spectrum: p[k] = real^2 + imag^2
            for k in 0..<numFreqBins {
                let re = real[k]
                let im = imag[k]
                // Match HF ordering: sqrt(re^2 + im^2) then squared.
                let mag = sqrtf(re * re + im * im)
                power[k] = mag * mag
            }

            // Mel projection: mel[i] = sum_k mel_rows[i][k] * power[k]
            var melRow = [Float](repeating: 0, count: numMelFilters)
            for i in 0..<numMelFilters {
                var acc: Float = 0
                melRows[i].withUnsafeBufferPointer { mPtr in
                    power.withUnsafeBufferPointer { pPtr in
                        vDSP_dotpr(mPtr.baseAddress!, 1, pPtr.baseAddress!, 1, &acc, vDSP_Length(numFreqBins))
                    }
                }
                melRow[i] = log(acc + logGuard)
            }
            logMelFrames[t] = melRow
        }

        // Per-mel-bin normalization over time.
        var mean = [Float](repeating: 0, count: numMelFilters)
        var std = [Float](repeating: 0, count: numMelFilters)
        let nT = Float(numFrames)
        for t in 0..<numFrames {
            for i in 0..<numMelFilters {
                mean[i] += logMelFrames[t][i]
            }
        }
        for i in 0..<numMelFilters { mean[i] /= nT }
        // HF uses ``(len - 1)`` denominator for variance (Bessel's correction).
        let denom = max(nT - 1, 1)
        for t in 0..<numFrames {
            for i in 0..<numMelFilters {
                let d = logMelFrames[t][i] - mean[i]
                std[i] += d * d
            }
        }
        for i in 0..<numMelFilters { std[i] = sqrt(std[i] / denom) }

        var normalized = logMelFrames
        for t in 0..<numFrames {
            for i in 0..<numMelFilters {
                normalized[t][i] = (normalized[t][i] - mean[i]) / (std[i] + epsilon)
            }
        }

        let mask = [Int32](repeating: 1, count: numFrames)
        return Features(mel: normalized, attentionMask: mask)
    }
}
