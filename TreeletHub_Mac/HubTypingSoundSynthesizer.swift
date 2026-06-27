import AVFoundation

/// 程序化合成机械轴体敲击音：多阶段物理模型 + 多振荡器 + 滤波噪声 + 随机抖动。
@MainActor
final class HubTypingSoundSynthesizer {
    static let shared = HubTypingSoundSynthesizer()

    enum Style {
        case blueSwitch
        case redSwitch
        case brownSwitch
    }

    enum KeyKind {
        case regular
        case space
        case enter
        case backspace
    }

    private enum NoiseFilter {
        case highPass(cutoffHz: Double)
        case lowPass(cutoffHz: Double)
        case bandPass(lowHz: Double, highHz: Double)
    }

    /// 单次按键的完整声学参数（合成前会叠加 ±5% 随机抖动）。
    private struct SwitchProfile {
        let noiseFilter: NoiseFilter
        let noiseDuration: Double
        let noiseGain: Float
        let noiseAttack: Double
        let noiseDecay: Double

        let fundamentalHz: Double
        let harmonics: [(ratio: Double, gain: Float)]
        let toneGain: Float
        let toneAttack: Double
        let toneDecayFast: Double
        let toneDecaySlow: Double

        let pingFrequencyHz: Double
        let pingGain: Float
        let pingDecay: Double

        let totalDuration: Double
        let masterGain: Float

        func scaled(
            frequencyScale: Double,
            durationScale: Double,
            noiseGainScale: Float,
            toneGainScale: Float,
            masterGainScale: Float
        ) -> SwitchProfile {
            SwitchProfile(
                noiseFilter: noiseFilter,
                noiseDuration: noiseDuration * durationScale,
                noiseGain: noiseGain * noiseGainScale,
                noiseAttack: noiseAttack,
                noiseDecay: noiseDecay * durationScale,
                fundamentalHz: fundamentalHz * frequencyScale,
                harmonics: harmonics,
                toneGain: toneGain * toneGainScale,
                toneAttack: toneAttack,
                toneDecayFast: toneDecayFast * durationScale,
                toneDecaySlow: toneDecaySlow * durationScale,
                pingFrequencyHz: pingFrequencyHz * frequencyScale,
                pingGain: pingGain,
                pingDecay: pingDecay * durationScale,
                totalDuration: totalDuration * durationScale,
                masterGain: masterGain * masterGainScale
            )
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConfigured = false

    private init() {}

    func play(style: Style, keyCode: UInt16) {
        play(style: style, keyKind: keyKind(forKeyCode: keyCode))
    }

    func play(style: Style, keyKind: KeyKind) {
        configureIfNeeded()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let profile = jitteredProfile(base: baseProfile(for: style, keyKind: keyKind))
        guard let buffer = makeClickBuffer(format: format, profile: profile) else { return }

        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        try? engine.start()
        isConfigured = true
    }

    private func keyKind(forKeyCode keyCode: UInt16) -> KeyKind {
        switch keyCode {
        case 49: return .space
        case 36, 76: return .enter
        case 51, 117: return .backspace
        default: return .regular
        }
    }

    private func baseProfile(for style: Style, keyKind: KeyKind) -> SwitchProfile {
        let base: SwitchProfile
        switch style {
        case .blueSwitch:
            // 青轴：高通噪声瞬态 + 高频谐振，整体短促清脆。
            base = SwitchProfile(
                noiseFilter: .highPass(cutoffHz: 3_500),
                noiseDuration: 0.003,
                noiseGain: 0.82,
                noiseAttack: 0.0015,
                noiseDecay: 0.0028,
                fundamentalHz: 800,
                harmonics: [(1.52, 0.28), (2.10, 0.12)],
                toneGain: 0.58,
                toneAttack: 0.002,
                toneDecayFast: 0.0045,
                toneDecaySlow: 0.018,
                pingFrequencyHz: 4_200,
                pingGain: 0.06,
                pingDecay: 0.012,
                totalDuration: 0.030,
                masterGain: 0.56
            )
        case .redSwitch:
            // 红轴：低通噪声 + 低频木质共鸣，线性闷响。
            base = SwitchProfile(
                noiseFilter: .lowPass(cutoffHz: 800),
                noiseDuration: 0.005,
                noiseGain: 0.48,
                noiseAttack: 0.002,
                noiseDecay: 0.0045,
                fundamentalHz: 180,
                harmonics: [(1.55, 0.22), (2.35, 0.08)],
                toneGain: 0.72,
                toneAttack: 0.0025,
                toneDecayFast: 0.006,
                toneDecaySlow: 0.038,
                pingFrequencyHz: 920,
                pingGain: 0.04,
                pingDecay: 0.022,
                totalDuration: 0.045,
                masterGain: 0.50
            )
        case .brownSwitch:
            // 茶轴：带通摩擦感 + 中低频双谐振，介于青红之间。
            base = SwitchProfile(
                noiseFilter: .bandPass(lowHz: 1_000, highHz: 2_000),
                noiseDuration: 0.004,
                noiseGain: 0.38,
                noiseAttack: 0.0018,
                noiseDecay: 0.0035,
                fundamentalHz: 300,
                harmonics: [(2.0, 0.35), (2.65, 0.10)],
                toneGain: 0.62,
                toneAttack: 0.002,
                toneDecayFast: 0.0055,
                toneDecaySlow: 0.028,
                pingFrequencyHz: 1_650,
                pingGain: 0.05,
                pingDecay: 0.016,
                totalDuration: 0.040,
                masterGain: 0.52
            )
        }

        return adjustedProfile(base, for: keyKind)
    }

    private func adjustedProfile(_ profile: SwitchProfile, for keyKind: KeyKind) -> SwitchProfile {
        switch keyKind {
        case .regular:
            return profile
        case .space:
            return profile.scaled(
                frequencyScale: 0.78,
                durationScale: 1.18,
                noiseGainScale: 0.92,
                toneGainScale: 1.08,
                masterGainScale: 1.06
            )
        case .enter:
            return profile.scaled(
                frequencyScale: 0.90,
                durationScale: 1.10,
                noiseGainScale: 1.04,
                toneGainScale: 1.06,
                masterGainScale: 1.08
            )
        case .backspace:
            return profile.scaled(
                frequencyScale: 1.06,
                durationScale: 0.92,
                noiseGainScale: 1.08,
                toneGainScale: 0.96,
                masterGainScale: 1.02
            )
        }
    }

    /// 每次按键对频率、衰减、音量施加 ±5% 抖动，避免连打时的电子重复感。
    private func jitteredProfile(base: SwitchProfile) -> SwitchProfile {
        SwitchProfile(
            noiseFilter: base.noiseFilter,
            noiseDuration: jitter(base.noiseDuration),
            noiseGain: jitter(base.noiseGain),
            noiseAttack: jitter(base.noiseAttack),
            noiseDecay: jitter(base.noiseDecay),
            fundamentalHz: jitter(base.fundamentalHz),
            harmonics: base.harmonics.map { (jitter($0.ratio), jitter($0.gain)) },
            toneGain: jitter(base.toneGain),
            toneAttack: jitter(base.toneAttack),
            toneDecayFast: jitter(base.toneDecayFast),
            toneDecaySlow: jitter(base.toneDecaySlow),
            pingFrequencyHz: jitter(base.pingFrequencyHz),
            pingGain: jitter(base.pingGain),
            pingDecay: jitter(base.pingDecay),
            totalDuration: jitter(base.totalDuration, range: 0.96...1.04),
            masterGain: jitter(base.masterGain)
        )
    }

    private func jitter(_ value: Double, range: ClosedRange<Double> = 0.97...1.03) -> Double {
        value * Double.random(in: range)
    }

    private func jitter(_ value: Float, range: ClosedRange<Double> = 0.97...1.03) -> Float {
        value * Float(Double.random(in: range))
    }

    private func makeClickBuffer(format: AVAudioFormat, profile: SwitchProfile) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * profile.totalDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        var lpStateA = 0.0
        var lpStateB = 0.0

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate

            // 1) 触点/触底瞬态：滤波白噪声 burst
            let rawNoise = time < profile.noiseDuration ? Double.random(in: -1...1) : 0
            let filteredNoise = filterNoise(
                rawNoise,
                filter: profile.noiseFilter,
                sampleRate: sampleRate,
                lpStateA: &lpStateA,
                lpStateB: &lpStateB
            )
            let noiseSample = filteredNoise
                * noiseEnvelope(time: time, attack: profile.noiseAttack, decay: profile.noiseDecay)
                * Double(profile.noiseGain)

            // 2) 腔体共鸣：基频 + 非整数倍谐波叠加
            let toneSample = resonanceSample(time: time, profile: profile)

            // 3) 尾音弹簧金属 Ping
            let pingSample = sin(2 * Double.pi * profile.pingFrequencyHz * time)
                * exp(-time / profile.pingDecay)
                * Double(profile.pingGain)

            let mixed = (noiseSample + toneSample + pingSample) * Double(profile.masterGain)
            samples[frame] = Float(max(-1, min(1, mixed)))
        }

        return buffer
    }

    private func noiseEnvelope(time: Double, attack: Double, decay: Double) -> Double {
        guard attack > 0 else { return exp(-time / decay) }
        let attackPhase = min(1, time / attack)
        return attackPhase * exp(-time / decay)
    }

    /// 双阶段 ADSR：5ms 内快速释放 70% 能量，余下 30% 在 25~40ms 缓慢衰减。
    private func toneEnvelope(time: Double, profile: SwitchProfile) -> Double {
        let attack = min(1, time / profile.toneAttack)
        let fast = exp(-time / profile.toneDecayFast)
        let slow = 0.30 * exp(-max(0, time - profile.toneDecayFast) / profile.toneDecaySlow)
        return attack * (0.70 * fast + slow)
    }

    private func resonanceSample(time: Double, profile: SwitchProfile) -> Double {
        let envelope = toneEnvelope(time: time, profile: profile) * Double(profile.toneGain)
        var tone = sin(2 * Double.pi * profile.fundamentalHz * time)
        for harmonic in profile.harmonics {
            tone += Double(harmonic.gain) * sin(2 * Double.pi * profile.fundamentalHz * harmonic.ratio * time)
        }
        return tone * envelope
    }

    private func filterNoise(
        _ sample: Double,
        filter: NoiseFilter,
        sampleRate: Double,
        lpStateA: inout Double,
        lpStateB: inout Double
    ) -> Double {
        switch filter {
        case .highPass(let cutoffHz):
            let lowPassed = onePoleLowPass(sample, cutoffHz: cutoffHz, sampleRate: sampleRate, state: &lpStateA)
            return sample - lowPassed
        case .lowPass(let cutoffHz):
            return onePoleLowPass(sample, cutoffHz: cutoffHz, sampleRate: sampleRate, state: &lpStateA)
        case .bandPass(let lowHz, let highHz):
            let highPassed = sample - onePoleLowPass(sample, cutoffHz: lowHz, sampleRate: sampleRate, state: &lpStateA)
            return onePoleLowPass(highPassed, cutoffHz: highHz, sampleRate: sampleRate, state: &lpStateB)
        }
    }

    private func onePoleLowPass(
        _ sample: Double,
        cutoffHz: Double,
        sampleRate: Double,
        state: inout Double
    ) -> Double {
        let rc = 1.0 / (2.0 * Double.pi * cutoffHz)
        let alpha = (1.0 / sampleRate) / (rc + (1.0 / sampleRate))
        state += alpha * (sample - state)
        return state
    }
}
