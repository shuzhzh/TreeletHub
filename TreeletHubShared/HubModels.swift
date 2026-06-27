import Foundation

public enum HubSlotKind: String, Codable, Equatable, Sendable {
    case app
    case shortcut
}

public enum HubShortcutKind: String, Codable, Equatable, Sendable {
    case volume
    case brightness
    case mediaTransport
    case screenshotFull
    case screenshotSelection
    case selectAll
    case copy
    case paste
    case openURL
}

/// 九宫格单格配置（0...8）。`bundleIdentifier` 为空表示该格未配置。
/// `iconPNG` 仅用于局域网同步到 iOS 展示；Mac 本地持久化应写入不含图标的精简结构。
public struct HubSlotConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: HubSlotKind
    public var bundleIdentifier: String?
    public var displayName: String?
    public var shortcutKind: HubShortcutKind?
    public var shortcutPayload: String?
    /// Mac 端生成的应用图标 PNG（可选）；JSON 中编码为 Base64。
    public var iconPNG: Data?

    public init(
        id: Int,
        kind: HubSlotKind = .app,
        bundleIdentifier: String? = nil,
        displayName: String? = nil,
        shortcutKind: HubShortcutKind? = nil,
        shortcutPayload: String? = nil,
        iconPNG: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.shortcutKind = shortcutKind
        self.shortcutPayload = shortcutPayload
        self.iconPNG = iconPNG
    }

    public var isEmpty: Bool {
        switch kind {
        case .app:
            return bundleIdentifier == nil || bundleIdentifier?.isEmpty == true
        case .shortcut:
            return shortcutKind == nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case bundleIdentifier
        case displayName
        case shortcutKind
        case shortcutPayload
        case iconPNG
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(HubSlotKind.self, forKey: .kind) ?? .app
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        shortcutKind = try c.decodeIfPresent(HubShortcutKind.self, forKey: .shortcutKind)
        shortcutPayload = try c.decodeIfPresent(String.self, forKey: .shortcutPayload)
        iconPNG = try c.decodeIfPresent(Data.self, forKey: .iconPNG)
    }
}

/// 九宫格分页配置（每页固定 9 格，`id` 用作稳定页面标识）。
public struct HubPageConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var slots: [HubSlotConfig]

    public init(id: Int, title: String, slots: [HubSlotConfig]? = nil) {
        self.id = id
        self.title = title
        if let slots, slots.count == 9 {
            self.slots = slots.enumerated().map { index, slot in
                HubSlotConfig(
                    id: index,
                    kind: slot.kind,
                    bundleIdentifier: slot.bundleIdentifier,
                    displayName: slot.displayName,
                    shortcutKind: slot.shortcutKind,
                    shortcutPayload: slot.shortcutPayload,
                    iconPNG: slot.iconPNG
                )
            }
        } else {
            self.slots = (0..<9).map { HubSlotConfig(id: $0) }
        }
    }
}

public enum HubService {
    public static let bonjourType = "_treelethub._tcp"
    public static let bonjourDomain: String? = nil
    public static let maxTabs = 5
}
