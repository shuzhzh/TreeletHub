import AVFoundation

/// 程序化合成机械键盘 / 打字机敲击音。
///
/// 声学模型（对齐真实按键录音的结构）：
/// 1. 触发瞬态：亚毫秒起音的滤波噪声（青轴 click jacket、茶轴触感段落、打字机字锤拍击）；
/// 2. 触底撞击：延迟约 8~12ms 的第二段瞬态，是声音的主体能量（红轴只有这一段）；
/// 3. 外壳共鸣：从触底开始的若干阻尼正弦模态（100~600Hz），持续 50~120ms，决定「厚度」；
/// 4. 弹簧 ping：3~5kHz 微弱长尾。
/// 每键叠加随机抖动 + 按键位的固定立体声声像；多声部并发保证快速连打不排队。
@MainActor
final class HubTypingSoundSynthesizer {
    static let shared = HubTypingSoundSynthesizer()

    enum Style {
        case blueSwitch
        case redSwitch
        case brownSwitch
        case typewriter
    }

    enum KeyKind {
        case regular
        case space
        case enter
        case backspace
    }

    /// 按下 / 松开两个阶段（松开为轻微回弹声）。
    enum Phase {
        case press
        case release
    }

    private enum NoiseFilter {
        case highPass(cutoffHz: Double)
        case lowPass(cutoffHz: Double)
        case bandPass(lowHz: Double, highHz: Double)
    }

    /// 一段滤波白噪声瞬态（触发咔哒 / 触底撞击）。
    private struct NoiseBurst {
        var offset: Double
        var filter: NoiseFilter
        var duration: Double
        var gain: Double
        var attack: Double
        var decay: Double
    }

    /// 一个阻尼正弦模态（外壳共鸣 / 金属 ping / 铃铛分音）。
    private struct ToneMode {
        var offset: Double
        var frequencyHz: Double
        var gain: Double
        var decay: Double
    }

    private struct SoundProfile {
        var bursts: [NoiseBurst]
        var modes: [ToneMode]
        var totalDuration: Double
        var masterGain: Double
    }

    private static let sampleRate: Double = 44_100
    private static let voiceCount = 6

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoiceIndex = 0
    private var isConfigured = false

    private init() {}

    func play(style: Style, keyCode: UInt16, phase: Phase = .press) {
        let kind = keyKind(forKeyCode: keyCode)
        let profile: SoundProfile
        switch phase {
        case .press:
            profile = jittered(pressProfile(style: style, keyKind: kind))
        case .release:
            profile = jittered(releaseProfile(style: style))
        }
        let pan = kind == .space ? 0 : Self.stablePan(forKeyCode: keyCode)
        playProfile(profile, pan: pan)
    }

    // MARK: - 播放

    private func playProfile(_ profile: SoundProfile, pan: Double) {
        configureIfNeeded()
        guard !voices.isEmpty else { return }
        guard let buffer = renderBuffer(profile: profile, pan: pan) else { return }

        let voice = voices[nextVoiceIndex]
        nextVoiceIndex = (nextVoiceIndex + 1) % voices.count
        // 复用最旧的声部：先清空其队列，保证新按键即时发声且可与其他声部叠加。
        voice.stop()
        voice.scheduleBuffer(buffer, completionHandler: nil)
        voice.play()
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else { return }
        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
        engine.mainMixerNode.outputVolume = 1
        try? engine.start()
        isConfigured = true
    }

    /// 键位 → 固定声像（±0.22），模拟键盘不同位置的空间感；同一键每次声像一致。
    private static func stablePan(forKeyCode keyCode: UInt16) -> Double {
        let hashed = (UInt32(keyCode) &* 2_654_435_761) % 1000
        return (Double(hashed) / 1000 - 0.5) * 0.44
    }

    private func keyKind(forKeyCode keyCode: UInt16) -> KeyKind {
        switch keyCode {
        case 49: return .space
        case 36, 76: return .enter
        case 51, 117: return .backspace
        default: return .regular
        }
    }

    // MARK: - 按下音色

    private func pressProfile(style: Style, keyKind: KeyKind) -> SoundProfile {
        if style == .typewriter, keyKind == .enter {
            return typewriterBellProfile()
        }
        let base = baseProfile(for: style)
        return adjusted(base, for: keyKind)
    }

    private func baseProfile(for style: Style) -> SoundProfile {
        switch style {
        case .blueSwitch:
            // 清脆的 click jacket + 明亮触底 + 高频弹簧尾音。
            return SoundProfile(
                bursts: [
                    NoiseBurst(offset: 0, filter: .highPass(cutoffHz: 3_800), duration: 0.002, gain: 0.85, attack: 0.0002, decay: 0.0018),
                    NoiseBurst(offset: 0.011, filter: .bandPass(lowHz: 1_300, highHz: 3_200), duration: 0.0035, gain: 0.7, attack: 0.0003, decay: 0.003),
                ],
                modes: [
                    ToneMode(offset: 0, frequencyHz: 1_750, gain: 0.08, decay: 0.012),
                    ToneMode(offset: 0.011, frequencyHz: 620, gain: 0.13, decay: 0.02),
                    ToneMode(offset: 0.011, frequencyHz: 185, gain: 0.24, decay: 0.05),
                    ToneMode(offset: 0.011, frequencyHz: 4_150, gain: 0.03, decay: 0.055),
                ],
                totalDuration: 0.12,
                masterGain: 0.62
            )
        case .redSwitch:
            // 线性轴：无触发声，只有触底 thock + 深沉外壳共鸣。
            return SoundProfile(
                bursts: [
                    NoiseBurst(offset: 0.002, filter: .lowPass(cutoffHz: 1_100), duration: 0.005, gain: 0.75, attack: 0.0004, decay: 0.0045),
                ],
                modes: [
                    ToneMode(offset: 0.002, frequencyHz: 430, gain: 0.1, decay: 0.018),
                    ToneMode(offset: 0.002, frequencyHz: 150, gain: 0.26, decay: 0.055),
                    ToneMode(offset: 0.002, frequencyHz: 95, gain: 0.16, decay: 0.07),
                    ToneMode(offset: 0.002, frequencyHz: 2_800, gain: 0.012, decay: 0.03),
                ],
                totalDuration: 0.13,
                masterGain: 0.5
            )
        case .brownSwitch:
            // 段落轴：轻微触感摩擦 + 圆润触底，介于青红之间。
            return SoundProfile(
                bursts: [
                    NoiseBurst(offset: 0, filter: .bandPass(lowHz: 1_200, highHz: 2_800), duration: 0.0018, gain: 0.32, attack: 0.0002, decay: 0.0016),
                    NoiseBurst(offset: 0.009, filter: .lowPass(cutoffHz: 2_000), duration: 0.0045, gain: 0.68, attack: 0.0003, decay: 0.004),
                ],
                modes: [
                    ToneMode(offset: 0.009, frequencyHz: 520, gain: 0.12, decay: 0.02),
                    ToneMode(offset: 0.009, frequencyHz: 168, gain: 0.26, decay: 0.05),
                    ToneMode(offset: 0.009, frequencyHz: 105, gain: 0.13, decay: 0.065),
                    ToneMode(offset: 0.009, frequencyHz: 3_400, gain: 0.018, decay: 0.04),
                ],
                totalDuration: 0.12,
                masterGain: 0.56
            )
        case .typewriter:
            // 字锤拍击滚筒：尖锐金属拍击 + 木质机身共鸣。
            return SoundProfile(
                bursts: [
                    NoiseBurst(offset: 0, filter: .highPass(cutoffHz: 2_200), duration: 0.0025, gain: 0.95, attack: 0.0002, decay: 0.002),
                    NoiseBurst(offset: 0.005, filter: .bandPass(lowHz: 400, highHz: 1_600), duration: 0.005, gain: 0.65, attack: 0.0003, decay: 0.0045),
                ],
                modes: [
                    ToneMode(offset: 0, frequencyHz: 3_100, gain: 0.07, decay: 0.025),
                    ToneMode(offset: 0.005, frequencyHz: 240, gain: 0.22, decay: 0.045),
                    ToneMode(offset: 0.005, frequencyHz: 130, gain: 0.12, decay: 0.06),
                ],
                totalDuration: 0.13,
                masterGain: 0.6
            )
        }
    }

    /// 打字机回车：机械回位闷响 + 经典「叮」铃铛（非整数倍分音的钟声衰减）。
    private func typewriterBellProfile() -> SoundProfile {
        SoundProfile(
            bursts: [
                NoiseBurst(offset: 0, filter: .lowPass(cutoffHz: 900), duration: 0.006, gain: 0.7, attack: 0.0004, decay: 0.005),
                NoiseBurst(offset: 0.022, filter: .highPass(cutoffHz: 3_000), duration: 0.0015, gain: 0.35, attack: 0.0002, decay: 0.0013),
            ],
            modes: [
                ToneMode(offset: 0, frequencyHz: 150, gain: 0.2, decay: 0.05),
                ToneMode(offset: 0.022, frequencyHz: 2_093, gain: 0.4, decay: 0.32),
                ToneMode(offset: 0.022, frequencyHz: 2_093 * 2.756, gain: 0.14, decay: 0.17),
                ToneMode(offset: 0.022, frequencyHz: 2_093 * 5.4, gain: 0.05, decay: 0.08),
            ],
            totalDuration: 0.7,
            masterGain: 0.5
        )
    }

    /// 空格 / 回车 / 退格的物理差异：更大的键帽与稳定器 → 更低频、更长的共鸣。
    private func adjusted(_ profile: SoundProfile, for keyKind: KeyKind) -> SoundProfile {
        let frequencyScale: Double
        let durationScale: Double
        let gainScale: Double
        switch keyKind {
        case .regular:
            return profile
        case .space:
            frequencyScale = 0.76
            durationScale = 1.22
            gainScale = 1.1
        case .enter:
            frequencyScale = 0.88
            durationScale = 1.12
            gainScale = 1.06
        case .backspace:
            frequencyScale = 1.08
            durationScale = 0.92
            gainScale = 1.0
        }
        var p = profile
        p.modes = p.modes.map { mode in
            var m = mode
            m.frequencyHz *= frequencyScale
            m.decay *= durationScale
            return m
        }
        p.totalDuration *= durationScale
        p.masterGain *= gainScale
        return p
    }

    // MARK: - 松键音色

    /// 松键回弹：短促高频轻响，音量远低于按下（红轴几乎不可闻）。
    private func releaseProfile(style: Style) -> SoundProfile {
        let master: Double
        switch style {
        case .blueSwitch: master = 0.2
        case .brownSwitch: master = 0.15
        case .redSwitch: master = 0.11
        case .typewriter: master = 0.16
        }
        return SoundProfile(
            bursts: [
                NoiseBurst(offset: 0, filter: .highPass(cutoffHz: 3_000), duration: 0.0018, gain: 0.5, attack: 0.0002, decay: 0.0016),
            ],
            modes: [
                ToneMode(offset: 0, frequencyHz: 600, gain: 0.05, decay: 0.012),
                ToneMode(offset: 0, frequencyHz: 4_150, gain: style == .blueSwitch ? 0.02 : 0.008, decay: 0.03),
            ],
            totalDuration: 0.05,
            masterGain: master
        )
    }

    // MARK: - 抖动（避免连打的电子重复感）

    private func jittered(_ profile: SoundProfile) -> SoundProfile {
        var p = profile
        p.bursts = p.bursts.map { burst in
            var b = burst
            if b.offset > 0 { b.offset *= Double.random(in: 0.82...1.22) }
            b.gain *= Double.random(in: 0.85...1.12)
            b.decay *= Double.random(in: 0.94...1.08)
            return b
        }
        p.modes = p.modes.map { mode in
            var m = mode
            m.frequencyHz *= Double.random(in: 0.965...1.035)
            m.gain *= Double.random(in: 0.85...1.12)
            m.decay *= Double.random(in: 0.94...1.08)
            return m
        }
        p.masterGain *= Double.random(in: 0.88...1.08)
        return p
    }

    // MARK: - 渲染

    private func renderBuffer(profile: SoundProfile, pan: Double) -> AVAudioPCMBuffer? {
        let sampleRate = Self.sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * profile.totalDuration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return nil }

        let frames = Int(frameCount)
        var mono = [Double](repeating: 0, count: frames)

        for burst in profile.bursts {
            renderBurst(burst, sampleRate: sampleRate, into: &mono)
        }
        for mode in profile.modes {
            renderMode(mode, sampleRate: sampleRate, into: &mono)
        }

        // 等功率声像。
        let theta = (pan.clamped(to: -1...1) + 1) * Double.pi / 4
        let leftGain = cos(theta)
        let rightGain = sin(theta)

        for frame in 0..<frames {
            let mixed = max(-1, min(1, mono[frame] * profile.masterGain))
            left[frame] = Float(mixed * leftGain)
            right[frame] = Float(mixed * rightGain)
        }
        return buffer
    }

    private func renderBurst(_ burst: NoiseBurst, sampleRate: Double, into samples: inout [Double]) {
        let start = max(0, Int(burst.offset * sampleRate))
        let end = min(samples.count, start + Int(burst.duration * sampleRate))
        guard start < end else { return }

        var lpStateA = 0.0
        var lpStateB = 0.0
        for frame in start..<end {
            let t = Double(frame - start) / sampleRate
            let raw = Double.random(in: -1...1)
            let filtered = filterNoise(raw, filter: burst.filter, sampleRate: sampleRate, lpStateA: &lpStateA, lpStateB: &lpStateB)
            let attack = burst.attack > 0 ? min(1, t / burst.attack) : 1
            samples[frame] += filtered * attack * exp(-t / burst.decay) * burst.gain
        }
    }

    private func renderMode(_ mode: ToneMode, sampleRate: Double, into samples: inout [Double]) {
        let start = max(0, Int(mode.offset * sampleRate))
        guard start < samples.count else { return }
        // 衰减到 -60dB 即可截断，避免整段都算正弦。
        let end = min(samples.count, start + Int(mode.decay * 7 * sampleRate))
        let attackDuration = 0.0004
        for frame in start..<end {
            let t = Double(frame - start) / sampleRate
            let attack = min(1, t / attackDuration)
            samples[frame] += sin(2 * Double.pi * mode.frequencyHz * t) * attack * exp(-t / mode.decay) * mode.gain
        }
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }

    private func renderBurst(_ burst: NoiseBurst, sampleRate: Double, into samples: inout [Double]) {
        let start = max(0, Int(burst.offset * sampleRate))
        let end = min(samples.count, start + Int(burst.duration * sampleRate))
        guard start < end else { return }

        var lpStateA = 0.0
        var lpStateB = 0.0
        for frame in start..<end {
            let t = Double(frame - start) / sampleRate
            let raw = Double.random(in: -1...1)
            let filtered = filterNoise(raw, filter: burst.filter, sampleRate: sampleRate, lpStateA: &lpStateA, lpStateB: &lpStateB)
            let attack = burst.attack > 0 ? min(1, t / burst.attack) : 1
            samples[frame] += filtered * attack * exp(-t / burst.decay) * burst.gain
        }
    }

    private func renderMode(_ mode: ToneMode, sampleRate: Double, into samples: inout [Double]) {
        let start = max(0, Int(mode.offset * sampleRate))
        guard start < samples.count else { return }
        // 衰减到 -60dB 即可截断，避免整段都算正弦。
        let end = min(samples.count, start + Int(mode.decay * 7 * sampleRate))
        let attackDuration = 0.0004
        for frame in start..<end {
            let t = Double(frame - start) / sampleRate
            let attack = min(1, t / attackDuration)
            samples[frame] += sin(2 * Double.pi * mode.frequencyHz * t) * attack * exp(-t / mode.decay) * mode.gain
        }
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
