import Foundation

/// iPhone ↔ Apple Watch 同步协议（WatchConnectivity）。
/// 真正的 Mac TCP 连接始终由 iPhone 上的 `HubIOSClient` 持有；Watch 镜像状态并转发操作。
public enum HubPhoneWatchSync {
    public static let snapshotContextKey = "snapshot"
    public static let messageOpKey = "op"
    /// 单页图标包：`page` / `epoch` + `s0`…`s8`（值为原始 PNG `Data`，避免 JSON Base64 膨胀）。
    public static let iconsPageOp = "iconsPage"

    public enum MessageOp: String, Sendable {
        case connectPin
        case stopScanning
        case disconnect
        case tap
        case control
        case requestSnapshot
        case iconsPage
    }

    public enum Phase: String, Codable, Sendable, Equatable {
        case idle
        case browsing
        case connecting
        case paired
    }

    /// 从 WCSession 字典解析单页图标。
    public static func parseIconsPage(_ message: [String: Any]) -> (page: Int, epoch: UInt64, icons: [Int: Data])? {
        guard let op = message[messageOpKey] as? String, op == MessageOp.iconsPage.rawValue || op == iconsPageOp
        else { return nil }
        let page: Int?
        if let v = message["page"] as? Int { page = v }
        else if let n = message["page"] as? NSNumber { page = n.intValue }
        else { page = nil }
        guard let page else { return nil }

        let epoch: UInt64
        if let v = message["epoch"] as? UInt64 { epoch = v }
        else if let v = message["epoch"] as? Int { epoch = UInt64(v) }
        else if let n = message["epoch"] as? NSNumber { epoch = n.uint64Value }
        else { epoch = 0 }

        var icons: [Int: Data] = [:]
        for slot in 0..<9 {
            if let data = message["s\(slot)"] as? Data, !data.isEmpty {
                icons[slot] = data
            }
        }
        return (page, epoch, icons)
    }
}

/// 推给 Watch 的精简快照（applicationContext，体积需 ≤ ~60KB）。
public struct HubWatchSyncSnapshot: Codable, Equatable, Sendable {
    public var phase: HubPhoneWatchSync.Phase
    public var pinInput: String
    public var lastError: String?
    public var didLoadCachedPairing: Bool
    public var pages: [HubPageConfig]
    public var layoutApplyEpoch: UInt64
    public var subscriptionActive: Bool
    /// Watch 是否与 iPhone 可达（仅 Watch 端本地写入，iPhone 推送时可忽略）。
    public var isPhoneReachable: Bool

    public init(
        phase: HubPhoneWatchSync.Phase = .idle,
        pinInput: String = "",
        lastError: String? = nil,
        didLoadCachedPairing: Bool = false,
        pages: [HubPageConfig] = [HubPageConfig(id: 0, title: "Apps")],
        layoutApplyEpoch: UInt64 = 0,
        subscriptionActive: Bool = false,
        isPhoneReachable: Bool = false
    ) {
        self.phase = phase
        self.pinInput = pinInput
        self.lastError = lastError
        self.didLoadCachedPairing = didLoadCachedPairing
        self.pages = pages
        self.layoutApplyEpoch = layoutApplyEpoch
        self.subscriptionActive = subscriptionActive
        self.isPhoneReachable = isPhoneReachable
    }

    /// 仅保留布局元数据（无图标），用于始终能塞进 `applicationContext` 的轻量快照。
    public static func pagesWithoutIcons(_ pages: [HubPageConfig]) -> [HubPageConfig] {
        pages.map { page in
            HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map {
                    var s = $0
                    s.iconPNG = nil
                    return s
                }
            )
        }
    }

    public var withoutIcons: HubWatchSyncSnapshot {
        var copy = self
        copy.pages = Self.pagesWithoutIcons(pages)
        return copy
    }

    public var hasAnyIcon: Bool {
        pages.contains { page in page.slots.contains { $0.iconPNG != nil } }
    }

    /// 把某页的原始图标 Data 合并进布局。
    public mutating func applyIcons(page pageId: Int, icons: [Int: Data]) {
        guard let idx = pages.firstIndex(where: { $0.id == pageId }) else { return }
        var page = pages[idx]
        page.slots = page.slots.map { slot in
            var s = slot
            if let data = icons[slot.id], !data.isEmpty {
                s.iconPNG = data
            }
            return s
        }
        pages[idx] = page
    }
}
