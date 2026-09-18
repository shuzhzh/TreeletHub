import Foundation

/// 键盘 HUD 可绑定的单个键位（字母/数字/符号）。
struct HubKeyboardKey: Hashable, Codable, Identifiable {
    let id: String
    var character: String { id }

    static let layoutRows: [[HubKeyboardKey]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="].map { HubKeyboardKey(id: $0) },
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"].map { HubKeyboardKey(id: $0) },
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"].map { HubKeyboardKey(id: $0) },
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"].map { HubKeyboardKey(id: $0) },
    ]

    static var allKeys: [HubKeyboardKey] {
        layoutRows.flatMap { $0 }
    }

    /// 将物理按键 keyCode（ANSI/US 布局）映射为布局键 id，与当前输入法输出的字符无关。
    static func id(forKeyCode keyCode: UInt16) -> String? {
        ansiKeyCodeToId[keyCode]
    }

    /// macOS 虚拟键码 → HUD 键位 id（与 HIToolbox Events.h kVK_ANSI_* 一致）。
    private static let ansiKeyCodeToId: [UInt16: String] = [
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6",
        0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0", 0x1B: "-", 0x18: "=",
        0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t",
        0x1F: "o", 0x20: "u", 0x22: "i", 0x23: "p", 0x21: "[", 0x1E: "]", 0x2A: "\\",
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
        0x26: "j", 0x28: "k", 0x25: "l", 0x29: ";", 0x27: "'",
        0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b", 0x2D: "n", 0x2E: "m",
        0x2B: ",", 0x2F: ".", 0x2C: "/",
    ]

    var displayLabel: String {
        switch id {
        case "\\": return "\\"
        default: return id.uppercased()
        }
    }
}

struct HubKeyboardSlot: Codable, Equatable {
    var bundleIdentifier: String
    var displayName: String
}

struct HubKeyboardHUDPersistedState: Codable {
    var bindings: [String: HubKeyboardSlot]
    var bookmarks: [String: Data]
    var didSeedDefaults: Bool
}

enum HubKeyboardHUDLayout {
    static let panelCornerRadius: CGFloat = 44
    /// 键位上统一显示的应用图标边长。
    static let keyIconDisplaySize: CGFloat = 80
    /// 应用名单行区域高度，保证同一行键位名称底对齐。
    static let keyNameRowHeight: CGFloat = 13
    /// 单个键帽高度（与 `keyIconDisplaySize` 匹配）。
    static let keyCellHeight: CGFloat = 134
    /// 与 `HubKeyboardHUDRootView` 布局一致的预估窗口，避免首次显示时先窄后宽。
    static var estimatedPanelSize: CGSize {
        // 最宽行为 13 键（Q 行含反斜杠键 88pt），左右 padding 44。
        let width: CGFloat = 12 * 100 + 88 + 12 * 10 + 88
        let height: CGFloat = 72 + 72 + 56 + (134 * 4) + 42 + 48
        return CGSize(width: width, height: height)
    }
}
