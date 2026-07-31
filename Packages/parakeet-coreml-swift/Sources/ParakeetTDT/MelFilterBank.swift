import Foundation

/// Constructs an HTK/Slaney-style mel filter bank identical to
/// ``librosa.filters.mel(..., htk=False, norm='slaney')``, which is what the
/// HF ``ParakeetFeatureExtractor`` builds at construction time.
///
/// Returned shape: ``(numMelFilters, numFrequencyBins)`` stored row-major, so
/// ``row[i][k]`` is the weight for mel filter ``i`` at FFT bin ``k``.
enum MelFilterBank {
    /// Slaney-style mel <-> hz conversion. Linear below 1 kHz, logarithmic
    /// above. Matches librosa's default for non-HTK mel.
    static func hzToMelSlaney(_ hz: Double) -> Double {
        let fMin = 0.0
        let fSp = 200.0 / 3.0
        let minLogHz = 1000.0
        let minLogMel = (minLogHz - fMin) / fSp
        let logstep = log(6.4) / 27.0

        if hz >= minLogHz {
            return minLogMel + log(hz / minLogHz) / logstep
        } else {
            return (hz - fMin) / fSp
        }
    }

    static func melToHzSlaney(_ mels: Double) -> Double {
        let fMin = 0.0
        let fSp = 200.0 / 3.0
        let minLogHz = 1000.0
        let minLogMel = (minLogHz - fMin) / fSp
        let logstep = log(6.4) / 27.0

        if mels >= minLogMel {
            return minLogHz * exp(logstep * (mels - minLogMel))
        } else {
            return fMin + fSp * mels
        }
    }

    /// Build the filter bank. All math done in Float64 then cast to Float32
    /// (matches librosa's behaviour).
    static func build(
        sampleRate: Double,
        nFFT: Int,
        numMelFilters: Int,
        fMin: Double = 0.0,
        fMax: Double? = nil
    ) -> (rows: [[Float]], numFreqBins: Int) {
        let numFreqBins = nFFT / 2 + 1
        let fMax = fMax ?? (sampleRate / 2.0)

        // Mel-scale breakpoints.
        let minMel = hzToMelSlaney(fMin)
        let maxMel = hzToMelSlaney(fMax)
        var mels = [Double]()
        mels.reserveCapacity(numMelFilters + 2)
        for i in 0..<(numMelFilters + 2) {
            let t = Double(i) / Double(numMelFilters + 1)
            mels.append(minMel + (maxMel - minMel) * t)
        }
        let hzBreakpoints = mels.map { melToHzSlaney($0) }

        // FFT bin center frequencies in Hz.
        var fftFreqs = [Double](repeating: 0, count: numFreqBins)
        for k in 0..<numFreqBins {
            fftFreqs[k] = Double(k) * sampleRate / Double(nFFT)
        }

        // Triangular filters with Slaney normalization.
        var rows = Array(
            repeating: [Float](repeating: 0.0, count: numFreqBins),
            count: numMelFilters
        )
        for i in 0..<numMelFilters {
            let lower = hzBreakpoints[i]
            let center = hzBreakpoints[i + 1]
            let upper = hzBreakpoints[i + 2]
            let enorm = 2.0 / (upper - lower)
            for k in 0..<numFreqBins {
                let f = fftFreqs[k]
                let lowerSlope = (f - lower) / (center - lower)
                let upperSlope = (upper - f) / (upper - center)
                let tri = max(0.0, min(lowerSlope, upperSlope))
                rows[i][k] = Float(tri * enorm)
            }
        }
        return (rows, numFreqBins)
    }
}
