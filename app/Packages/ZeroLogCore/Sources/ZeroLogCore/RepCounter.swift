import Foundation

// Counts repetitions from wrist accelerometer samples.
//
// Validated against MM-Fit (21 workouts, 616 labelled sets, real smartwatch
// accelerometers) with a subject-level holdout -- 14 workouts to tune, 7 unseen
// workouts to score. On the 404 held-out sets: 84.2% within +/-1 rep, and the
// 74% of sets reported `.high` are 99.7% within +/-1.
//
// This is a direct port of scripts/rep_counter.py and must stay numerically
// identical to it. RepCounterFixtureTests replays real MM-Fit sets through both
// and asserts the counts match, so a divergence fails the build rather than
// quietly degrading the product.
//
// PRODUCT RULE: code does the numbers. No model is involved in counting a rep.

public enum RepConfidence: String, Codable, Sendable {
    /// Two estimators agree. Log it silently; the user never taps.
    case high
    /// Estimators disagree a little. Show the number, invite a correction.
    case medium
    /// Not trustworthy. Ask for a tap; never present this as a fact.
    case low
}

public struct RepCount: Equatable, Sendable {
    public let reps: Int
    public let confidence: RepConfidence
    /// Peak-counting estimate, kept for debugging and for the "why" card.
    public let peakEstimate: Int
    /// Autocorrelation estimate. Zero means no periodicity was found.
    public let autocorrEstimate: Int
    public let activeSeconds: Double

    public init(reps: Int, confidence: RepConfidence, peakEstimate: Int = 0,
                autocorrEstimate: Int = 0, activeSeconds: Double = 0) {
        self.reps = reps
        self.confidence = confidence
        self.peakEstimate = peakEstimate
        self.autocorrEstimate = autocorrEstimate
        self.activeSeconds = activeSeconds
    }
}

/// Per-exercise calibration. Tuned on MM-Fit; see `RepCounter.profiles`.
public struct RepProfile: Equatable, Sendable {
    public let bandHighHz: Double
    public let minRepSeconds: Double
    /// Peak prominence threshold as a fraction of the signal's standard deviation.
    public let prominence: Double
    /// 2.0 for ALTERNATING movements, where one wrist legitimately sees half the
    /// set's reps. Getting this wrong is invisible to the cross-check.
    public let limbFactor: Double

    public init(bandHighHz: Double, minRepSeconds: Double,
                prominence: Double, limbFactor: Double = 1.0) {
        self.bandHighHz = bandHighHz
        self.minRepSeconds = minRepSeconds
        self.prominence = prominence
        self.limbFactor = limbFactor
    }
}

public enum RepCounter {

    // Reps live at roughly 0.3-1.0 Hz. Band generously around that.
    static let bandLowHz = 0.2
    static let minActiveSeconds = 4.0

    public static let defaultProfile = RepProfile(bandHighHz: 2.0, minRepSeconds: 0.55,
                                                  prominence: 0.40)

    /// Calibration per exercise, tuned on MM-Fit with a subject-level holdout.
    ///
    /// Per-exercise settings are legitimate rather than overfitting because the
    /// rules engine always knows which exercise is next -- calibration is free at
    /// runtime. That is also the ONLY defence against the blind spot documented
    /// on `count(...)`.
    ///
    /// `jumping_jacks` is deliberately absent: tuning scored 100% on the training
    /// workouts but fell to 83% on unseen athletes, so it keeps the generic
    /// profile. Never ship a calibration that loses on held-out subjects.
    public static let profiles: [String: RepProfile] = [
        "bicep_curls":             RepProfile(bandHighHz: 2.0, minRepSeconds: 0.40, prominence: 0.15),
        "dumbbell_rows":           RepProfile(bandHighHz: 2.0, minRepSeconds: 1.10, prominence: 0.25),
        "dumbbell_shoulder_press": RepProfile(bandHighHz: 1.5, minRepSeconds: 1.10, prominence: 0.55),
        "lateral_shoulder_raises": RepProfile(bandHighHz: 1.5, minRepSeconds: 1.10, prominence: 0.55),
        // lunges: 12% even after tuning. Alternating legs plus arm swing make the
        // wrist signal ambiguous. Treat as not auto-detectable; fall back to a tap.
        "lunges":                  RepProfile(bandHighHz: 2.0, minRepSeconds: 1.10, prominence: 0.55),
        "pushups":                 RepProfile(bandHighHz: 1.5, minRepSeconds: 1.10, prominence: 0.25),
        "situps":                   RepProfile(bandHighHz: 1.5, minRepSeconds: 0.90, prominence: 0.55),
        "squats":                  RepProfile(bandHighHz: 2.0, minRepSeconds: 1.10, prominence: 0.40),
        "tricep_extensions":       RepProfile(bandHighHz: 2.0, minRepSeconds: 0.40, prominence: 0.15),
    ]

    public static func profile(for exercise: String?) -> RepProfile {
        guard let key = exercise?.lowercased(), let p = profiles[key] else { return defaultProfile }
        return p
    }

    // MARK: - Public entry point

    /// Counts reps in one set.
    ///
    /// - Parameters:
    ///   - sampleRateHz: samples per second of the accelerometer stream.
    ///   - x, y, z: acceleration per axis, gravity excluded, in m/s^2 or g
    ///     (the pipeline is scale-invariant, but be consistent).
    ///   - exercise: the planned exercise key. ALWAYS pass this when known.
    ///
    /// IMPORTANT, learned from MM-Fit: the two estimators are **not
    /// independent**. Both measure the periodicity of this one wrist, so a
    /// systematic misreading fools them identically and still reports `.high`.
    /// On alternating bicep curls both returned exactly 5 against a true 10,
    /// confidently, on every single set. The cross-check catches NOISE, not
    /// misinterpretation -- only knowing the exercise catches that, which is why
    /// ZeroLog never guesses which exercise is being performed.
    public static func count(sampleRateHz fs: Double,
                            x: [Double], y: [Double], z: [Double],
                            exercise: String? = nil) -> RepCount {
        let p = profile(for: exercise)
        guard fs > 0, x.count == y.count, y.count == z.count, x.count > 8 else {
            return RepCount(reps: 0, confidence: .low)
        }

        let axis = movementAxis(x: x, y: y, z: z, fs: fs, bandHighHz: p.bandHighHz)
        let (s, e) = activeWindow(axis, fs: fs)
        let activeSeconds = Double(e - s) / fs
        if activeSeconds < minActiveSeconds {
            return RepCount(reps: 0, confidence: .low, activeSeconds: activeSeconds)
        }
        let seg = Array(axis[s..<e])

        // A watch resting on a bench produced "0 reps, medium" before this guard,
        // because zero peaks plus zero autocorrelation read as agreement.
        // Silence is an absence of evidence, so it must report low.
        if standardDeviation(seg) < 1e-6 {
            return RepCount(reps: 0, confidence: .low, activeSeconds: activeSeconds)
        }

        let nPeak = countByPeaks(seg, fs: fs, minRepSeconds: p.minRepSeconds,
                                 prominence: p.prominence)
        let nAuto = countByAutocorrelation(seg, fs: fs, bandHighHz: p.bandHighHz)

        func result(_ count: Double, _ conf: RepConfidence) -> RepCount {
            // A wrist sees only its own limb; limbFactor doubles for alternating work.
            RepCount(reps: Int((count * p.limbFactor).rounded()), confidence: conf,
                     peakEstimate: nPeak, autocorrEstimate: nAuto,
                     activeSeconds: activeSeconds)
        }

        if nAuto == 0 { return result(Double(nPeak), .medium) }
        let gap = abs(nPeak - nAuto)
        if gap <= 1 { return result(Double(nPeak), .high) }
        if gap <= 2 { return result(Double(nPeak + nAuto) / 2.0, .medium) }
        return result(Double(nPeak), .low)
    }

    // MARK: - Signal pipeline

    /// Projects the three axes onto the dominant direction of movement.
    ///
    /// CRITICAL: never use sqrt(x^2+y^2+z^2) for rep counting. Squaring a signal
    /// that swings either side of zero doubles its apparent frequency, so the peak
    /// counter reads ~2x the true rep count. This cost a 14%-accuracy false start.
    /// The projection below keeps the sign.
    static func movementAxis(x: [Double], y: [Double], z: [Double],
                             fs: Double, bandHighHz: Double) -> [Double] {
        var rows = [bandpass(x, fs: fs, lo: bandLowHz, hi: bandHighHz),
                    bandpass(y, fs: fs, lo: bandLowHz, hi: bandHighHz),
                    bandpass(z, fs: fs, lo: bandLowHz, hi: bandHighHz)]
        for i in 0..<3 {
            let m = rows[i].reduce(0, +) / Double(rows[i].count)
            rows[i] = rows[i].map { $0 - m }
        }

        // Covariance (unbiased, matching numpy.cov's default), then its dominant
        // eigenvector = the main direction of movement.
        let n = rows[0].count
        let denom = Double(max(n - 1, 1))
        var cov = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                var acc = 0.0
                for k in 0..<n { acc += rows[i][k] * rows[j][k] }
                cov[i][j] = acc / denom
            }
        }
        let v = dominantEigenvector(cov)

        var proj = [Double](repeating: 0, count: n)
        for k in 0..<n { proj[k] = v[0] * rows[0][k] + v[1] * rows[1][k] + v[2] * rows[2][k] }

        // The eigenvector sign is arbitrary. Fix it so peaks consistently mean
        // "concentric", using skewness, so the peak counter is reproducible.
        let skew = proj.reduce(0) { $0 + $1 * $1 * $1 }
        if skew < 0 { proj = proj.map { -$0 } }
        return proj
    }

    /// RBJ cookbook bandpass coefficients: (b0, b1, b2, a1, a2), a0 normalised.
    ///
    /// Deliberately portable rather than a scipy Butterworth, so Swift and Python
    /// run provably identical maths. Switching to it also improved held-out
    /// accuracy, so there was no price for the simplicity.
    static func biquadBandpass(lo: Double, hi: Double, fs: Double)
        -> (Double, Double, Double, Double, Double) {
        let f0 = (lo * hi).squareRoot()
        let q = f0 / max(hi - lo, 1e-9)
        let w0 = 2 * Double.pi * f0 / fs
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        return (alpha / a0, 0.0, -alpha / a0, (-2 * cosw) / a0, (1 - alpha) / a0)
    }

    static func applyBiquad(_ x: [Double],
                            _ co: (Double, Double, Double, Double, Double)) -> [Double] {
        let (b0, b1, b2, a1, a2) = co
        var out = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let v = x[i]
            let o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = v
            y2 = y1; y1 = o
            out[i] = o
        }
        return out
    }

    /// Zero-phase bandpass: forward then backward, cascaded for a steeper skirt.
    static func bandpass(_ x: [Double], fs: Double, lo: Double, hi: Double,
                         stages: Int = 2) -> [Double] {
        let nyq = fs / 2.0
        let hiClamped = min(hi, nyq * 0.95)
        if lo >= hiClamped {
            let m = x.reduce(0, +) / Double(max(x.count, 1))
            return x.map { $0 - m }
        }
        let co = biquadBandpass(lo: lo, hi: hiClamped, fs: fs)
        var y = x
        for _ in 0..<stages {
            y = applyBiquad(y, co)
            y = applyBiquad(y.reversed(), co).reversed()
        }
        return y
    }

    /// Trims to where the movement actually happens, so walking to the rack and
    /// re-gripping do not dilute the periodicity estimate.
    static func activeWindow(_ sig: [Double], fs: Double) -> (Int, Int) {
        let k = max(Int(0.5 * fs), 1)
        var env = [Double](repeating: 0, count: sig.count)
        // Centred moving average of |signal|, matching numpy.convolve(mode="same").
        let half = k / 2
        for i in 0..<sig.count {
            var acc = 0.0
            for j in (i - half)..<(i - half + k) where j >= 0 && j < sig.count {
                acc += abs(sig[j])
            }
            env[i] = acc / Double(k)
        }
        guard let mx = env.max(), mx > 0 else { return (0, sig.count) }
        let thr = 0.25 * mx
        guard let first = env.firstIndex(where: { $0 > thr }),
              let last = env.lastIndex(where: { $0 > thr }) else { return (0, sig.count) }
        return (first, last + 1)
    }

    // MARK: - Estimator 1: prominent peaks

    /// Replicates scipy.signal.find_peaks(distance:prominence:) including its
    /// ORDER OF OPERATIONS -- distance is applied before prominence. Changing the
    /// order changes the counts, so this must not be "tidied up".
    static func countByPeaks(_ sig: [Double], fs: Double,
                             minRepSeconds: Double, prominence: Double) -> Int {
        let threshold = max(prominence * standardDeviation(sig), 1e-6)
        let distance = max(Int(minRepSeconds * fs), 1)

        // 1. local maxima (scipy takes the midpoint of a plateau)
        var maxima: [Int] = []
        var i = 1
        while i < sig.count - 1 {
            if sig[i] > sig[i - 1] {
                var j = i
                while j < sig.count - 1 && sig[j + 1] == sig[i] { j += 1 }
                if sig[j] > sig[j + 1] { maxima.append((i + j) / 2) }
                i = j + 1
            } else {
                i += 1
            }
        }
        if maxima.isEmpty { return 0 }

        // 2. distance filter: keep by descending height, drop close neighbours
        var keep = [Bool](repeating: true, count: maxima.count)
        for idx in maxima.indices.sorted(by: { sig[maxima[$0]] > sig[maxima[$1]] }) {
            guard keep[idx] else { continue }
            var j = idx - 1
            while j >= 0 && maxima[idx] - maxima[j] < distance { keep[j] = false; j -= 1 }
            j = idx + 1
            while j < maxima.count && maxima[j] - maxima[idx] < distance { keep[j] = false; j += 1 }
        }
        let spaced = maxima.indices.filter { keep[$0] }.map { maxima[$0] }

        // 3. topographic prominence, searched over the whole signal
        var count = 0
        for p in spaced {
            let height = sig[p]
            var leftMin = height
            var k = p - 1
            while k >= 0 && sig[k] <= height { leftMin = min(leftMin, sig[k]); k -= 1 }
            var rightMin = height
            k = p + 1
            while k < sig.count && sig[k] <= height { rightMin = min(rightMin, sig[k]); k += 1 }
            if height - max(leftMin, rightMin) >= threshold { count += 1 }
        }
        return count
    }

    // MARK: - Estimator 2: autocorrelation period

    /// Independent-ish second opinion: find the dominant rep period, divide the
    /// set duration by it. See the blind-spot warning on `count(...)`.
    static func countByAutocorrelation(_ sig: [Double], fs: Double,
                                       bandHighHz: Double) -> Int {
        let n = sig.count
        guard n >= 8 else { return 0 }
        let mean = sig.reduce(0, +) / Double(n)
        let x = sig.map { $0 - mean }

        let lo = max(Int(fs / bandHighHz), 1)
        let hi = min(Int(fs / bandLowHz), n - 1)
        guard hi > lo else { return 0 }

        var zero = 0.0
        for v in x { zero += v * v }
        guard zero > 0 else { return 0 }

        var best = -Double.infinity
        var bestLag = -1
        var prev = 0.0, cur = 0.0
        for lag in (lo - 1)...(hi + 1) where lag >= 1 && lag < n {
            var acc = 0.0
            for k in 0..<(n - lag) { acc += x[k] * x[k + lag] }
            let norm = acc / zero
            if lag - 1 >= lo && lag - 1 <= hi && cur > prev && cur >= norm && cur > best {
                best = cur; bestLag = lag - 1
            }
            prev = cur; cur = norm
        }
        guard bestLag > 0 else { return 0 }
        let period = Double(bestLag) / fs
        return Int(((Double(n) / fs) / period).rounded())
    }

    // MARK: - Small numerics

    static func standardDeviation(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let m = v.reduce(0, +) / Double(v.count)
        let varSum = v.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (varSum / Double(v.count)).squareRoot()
    }

    /// Dominant eigenvector of a symmetric 3x3 matrix, by cyclic Jacobi rotation.
    /// Foundation-only on purpose: no Accelerate, so this builds and tests on
    /// Linux CI as well as on a watch.
    static func dominantEigenvector(_ m: [[Double]]) -> [Double] {
        var a = m
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<64 {
            // largest off-diagonal element
            var p = 0, q = 1
            var maxOff = abs(a[0][1])
            if abs(a[0][2]) > maxOff { maxOff = abs(a[0][2]); p = 0; q = 2 }
            if abs(a[1][2]) > maxOff { maxOff = abs(a[1][2]); p = 1; q = 2 }
            if maxOff < 1e-14 { break }

            let theta = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p])
            let c = cos(theta), s = sin(theta)
            var aNew = a
            for k in 0..<3 {
                aNew[p][k] = c * a[p][k] - s * a[q][k]
                aNew[q][k] = s * a[p][k] + c * a[q][k]
            }
            var aNew2 = aNew
            for k in 0..<3 {
                aNew2[k][p] = c * aNew[k][p] - s * aNew[k][q]
                aNew2[k][q] = s * aNew[k][p] + c * aNew[k][q]
            }
            a = aNew2
            var vNew = v
            for k in 0..<3 {
                vNew[k][p] = c * v[k][p] - s * v[k][q]
                vNew[k][q] = s * v[k][p] + c * v[k][q]
            }
            v = vNew
        }
        let eigenvalues = [a[0][0], a[1][1], a[2][2]]
        var bestIdx = 0
        for i in 1..<3 where eigenvalues[i] > eigenvalues[bestIdx] { bestIdx = i }
        return [v[0][bestIdx], v[1][bestIdx], v[2][bestIdx]]
    }
}
