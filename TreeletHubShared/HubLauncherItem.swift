import SwiftUI

/// 跨页快捷启动条目（page + slot 唯一）。
public struct HubLauncherItem: Identifiable, Equatable, Sendable {
    public let pageId: Int
    public let slot: HubSlotConfig

    public var id: String { "\(pageId)-\(slot.id)" }

    public init(pageId: Int, slot: HubSlotConfig) {
        self.pageId = pageId
        self.slot = slot
    }

    /// 蜂巢墙尾部的「添加」按钮（非真实槽位）。
    public static func addAffordance() -> HubLauncherItem {
        HubLauncherItem(pageId: -1, slot: HubSlotConfig(id: -1))
    }

    public var isAddAffordance: Bool { pageId < 0 }

    public var needsInlineControl: Bool {
        guard !isAddAffordance else { return false }
        guard slot.kind == .shortcut, let kind = slot.shortcutKind else { return false }
        return kind == .volume || kind == .brightness || kind == .mediaTransport
    }
}

public enum HubLauncherItems {
    /// 将多页非空槽位收成一条启动列表（保持 page 顺序）。
    public static func flattened(from pages: [HubPageConfig], includeEmpty: Bool = false) -> [HubLauncherItem] {
        pages.flatMap { page in
            page.slots
                .filter { includeEmpty || !$0.isEmpty }
                .map { HubLauncherItem(pageId: page.id, slot: $0) }
        }
    }

    /// 在列表末尾追加「+」添加入口。
    public static func flattenedWithAddAffordance(from pages: [HubPageConfig]) -> [HubLauncherItem] {
        flattened(from: pages) + [.addAffordance()]
    }
}

public extension HubShortcutKind {
    var hubLauncherSystemImage: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .mediaTransport: return "playpause.fill"
        case .screenshotFull, .screenshotSelection: return "camera.viewfinder"
        case .selectAll: return "checklist"
        case .copy: return "doc.on.doc.fill"
        case .paste: return "clipboard.fill"
        case .openURL: return "link"
        }
    }
}
