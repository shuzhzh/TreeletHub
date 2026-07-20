import AppKit

/// 根据所选预设播放键盘敲击音效。
/// 机械轴与打字机使用程序化合成（含松键回弹声）；其余预设映射到系统音色。
enum HubTypingSoundPlayer {
    static var activePreset: HubTypingSoundPreset = .none

    private static let systemClassicRegular = ["Tink", "Tink", "Tink", "Pop"]
    private static let crispRegular = ["Ping", "Tink", "Ping", "Pop"]
    private static let softRegular = ["Pop", "Purr", "Pop", "Purr"]

    private static func synthesizedStyle(for preset: HubTypingSoundPreset) -> HubTypingSoundSynthesizer.Style? {
        switch preset {
        case .mechanicalBlue: return .blueSwitch
        case .mechanicalRed: return .redSwitch
        case .mechanicalBrown: return .brownSwitch
        case .typewriter: return .typewriter
        case .none, .systemClassic, .crisp, .soft: return nil
        }
    }

    static func play(forKeyCode keyCode: UInt16) {
        play(preset: activePreset, keyCode: keyCode, phase: .press)
    }

    /// 松键回弹声：仅合成类预设播放（系统音色预设无对应素材）。
    static func playKeyUp(forKeyCode keyCode: UInt16) {
        guard synthesizedStyle(for: activePreset) != nil else { return }
        play(preset: activePreset, keyCode: keyCode, phase: .release)
    }

    static func playPreview(for preset: HubTypingSoundPreset) {
        play(preset: preset, keyCode: 0, phase: .press)
    }

    private static func play(
        preset: HubTypingSoundPreset,
        keyCode: UInt16,
        phase: HubTypingSoundSynthesizer.Phase
    ) {
        if let style = synthesizedStyle(for: preset) {
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: style, keyCode: keyCode, phase: phase)
            }
            return
        }
        guard phase == .press else { return }
        switch preset {
        case .systemClassic:
            playSystemMapped(keyCode: keyCode, regular: systemClassicRegular, space: "Bottle", enter: "Pop", backspace: "Tink")
        case .crisp:
            playSystemMapped(keyCode: keyCode, regular: crispRegular, space: "Ping", enter: "Tink", backspace: "Ping")
        case .soft:
            playSystemMapped(keyCode: keyCode, regular: softRegular, space: "Blow", enter: "Purr", backspace: "Pop")
        case .none, .mechanicalBlue, .mechanicalRed, .mechanicalBrown, .typewriter:
            return