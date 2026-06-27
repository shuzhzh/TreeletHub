import AppKit

/// 根据所选预设播放键盘敲击音效。
enum HubTypingSoundPlayer {
    static var activePreset: HubTypingSoundPreset = .none

    private static let systemClassicRegular = ["Tink", "Tink", "Tink", "Pop"]
    private static let typewriterRegular = ["Morse", "Tink", "Morse", "Pop"]
    private static let crispRegular = ["Ping", "Tink", "Ping", "Pop"]
    private static let softRegular = ["Pop", "Purr", "Pop", "Purr"]

    static func play(forKeyCode keyCode: UInt16) {
        switch activePreset {
        case .none:
            return
        case .systemClassic:
            playSystemMapped(
                keyCode: keyCode,
                regular: systemClassicRegular,
                space: "Bottle",
                enter: "Pop",
                backspace: "Tink"
            )
        case .mechanicalBlue:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .blueSwitch, keyCode: keyCode)
            }
        case .mechanicalRed:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .redSwitch, keyCode: keyCode)
            }
        case .mechanicalBrown:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .brownSwitch, keyCode: keyCode)
            }
        case .typewriter:
            playSystemMapped(
                keyCode: keyCode,
                regular: typewriterRegular,
                space: "Funk",
                enter: "Morse",
                backspace: "Tink"
            )
        case .crisp:
            playSystemMapped(
                keyCode: keyCode,
                regular: crispRegular,
                space: "Ping",
                enter: "Tink",
                backspace: "Ping"
            )
        case .soft:
            playSystemMapped(
                keyCode: keyCode,
                regular: softRegular,
                space: "Blow",
                enter: "Purr",
                backspace: "Pop"
            )
        }
    }

    static func playPreview(for preset: HubTypingSoundPreset) {
        guard preset != .none else { return }
        switch preset {
        case .none:
            return
        case .systemClassic:
            playSystemMapped(
                keyCode: 0,
                regular: systemClassicRegular,
                space: "Bottle",
                enter: "Pop",
                backspace: "Tink"
            )
        case .mechanicalBlue:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .blueSwitch, keyCode: 0)
            }
        case .mechanicalRed:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .redSwitch, keyCode: 0)
            }
        case .mechanicalBrown:
            Task { @MainActor in
                HubTypingSoundSynthesizer.shared.play(style: .brownSwitch, keyCode: 0)
            }
        case .typewriter:
            playSystemMapped(
                keyCode: 0,
                regular: typewriterRegular,
                space: "Funk",
                enter: "Morse",
                backspace: "Tink"
            )
        case .crisp:
            playSystemMapped(
                keyCode: 0,
                regular: crispRegular,
                space: "Ping",
                enter: "Tink",
                backspace: "Ping"
            )
        case .soft:
            playSystemMapped(
                keyCode: 0,
                regular: softRegular,
                space: "Blow",
                enter: "Purr",
                backspace: "Pop"
            )
        }
    }

    private static func playSystemMapped(
        keyCode: UInt16,
        regular: [String],
        space: String,
        enter: String,
        backspace: String
    ) {
        let name: String
        switch keyCode {
        case 49:
            name = space
        case 36, 76:
            name = enter
        case 51, 117:
            name = backspace
        default:
            name = regular.randomElement() ?? "Tink"
        }
        playNamedSystemSound(name)
    }

    private static func playNamedSystemSound(_ name: String, volume: Float = 0.55) {
        guard let template = NSSound(named: NSSound.Name(name)) else {
            NSSound.beep()
            return
        }
        guard let sound = template.copy() as? NSSound else {
            template.volume = volume
            template.play()
            return
        }
        sound.volume = volume
        sound.play()
    }
}
