#if os(iOS)
import Combine
import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// iOS 手机蜂窝列表：冷启动预填常用 App，添加/替换/删除逻辑对齐 Mac `HubGridStore`。
@MainActor
final class HubIOSAppGridStore: ObservableObject {
    @Published private(set) var pages: [HubPageConfig]

    init() {
        // 旧版本落盘的 token 快照图会盖住真实图标，按缓存策略版本一次性清掉。
        HubIOSAppGroup.migrateIconCacheIfNeeded()
        // 冷启动只做轻量读取，图标补全放到后台，别让首屏白屏几秒。
        pages = HubIOSAppGroup.hydratedPages(from: Self.normalizePages(HubIOSAppGroup.loadPages()))
        bootstrapTask = Task { [weak self] in await self?.bootstrap() }
    }

    private var bootstrapTask: Task<Void, Never>?

    /// 已含图标的页面（`pages` 始终保持 hydrated 状态，避免每次渲染都读盘）。
    var launcherPages: [HubPageConfig] { pages }

    /// 首次启动预填常用应用；之后每次进入前台清理已卸载应用。
    private func bootstrap() async {
        var loaded = pages
        if !HubIOSAppGroup.defaults.bool(forKey: HubIOSAppGroup.didApplyStarterKey) {
            let filledIds = loaded.flatMap { $0.slots.compactMap(\.bundleIdentifier) }
            let onlySystemDefaults = filledIds.isEmpty
                || filledIds.allSatisfy { $0.hasPrefix("com.apple.") }
            if onlySystemDefaults {
                let installed = await Task.detached(priority: .userInitiated) {
                    HubIOSInstalledApps.installedApps()
                }.value
                loaded = Self.makeStarterPages(installed: installed)
            }
            HubIOSAppGroup.defaults.set(true, forKey: HubIOSAppGroup.didApplyStarterKey)
        }
        pages = HubIOSAppGroup.hydratedPages(from: loaded)
        persist()
        await pruneAndPrefetch()
    }

    /// 进入前台时调用：等首启预填完成后，清掉已卸载的应用并补齐缺失图标。
    func refreshInstalledApps() async {
        await bootstrapTask?.value
        await pruneAndPrefetch()
    }

    /// 安装探测在后台线程完成，避免阻塞主线程。
    private func pruneAndPrefetch() async {
        let bundleIds = Set(pages.flatMap { $0.slots.compactMap(\.bundleIdentifier) }.filter { !$0.isEmpty })
        let installState: [String: Bool?] = await Task.detached(priority: .utility) {
            var result: [String: Bool?] = [:]
            for bid in bundleIds {
                result[bid] = HubIOSInstalledApps.isInstalled(bid)
            }
            return result
        }.value
        let pruned = HubIOSAppGroup.pruneUninstalled(from: pages) { bid in
            installState[bid] ?? nil
        }
        let hydrated = HubIOSAppGroup.hydratedPages(from: pruned)
        if hydrated != pages {
            pages = hydrated
            persist()
        }
        await prefetchMissingIcons()
    }

    /// 只为有 bundle id 的槽位补 App Store 官方 artwork。
    private func prefetchMissingIcons() async {
        var missing: [(bundleId: String, displayName: String?)] = []
        var seen = Set<String>()
        for page in pages {
            for slot in page.slots {
                guard let bid = slot.bundleIdentifier, !bid.isEmpty, seen.insert(bid).inserted else { continue }
                if HubIOSInstalledApps.isContactCall(bid) { continue }
                if HubIOSAppGroup.loadIcon(for: bid) != nil { continue }
                missing.append((bid, slot.displayName))
            }
        }
        guard !missing.isEmpty else { return }

        // 并行拉图（最多 4 路），避免十几个应用逐个等网络。
        let saved = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            var pending = missing[...]
            var inflight = 0
            var savedCount = 0
            func launchNext(_ group: inout TaskGroup<Bool>) {
                guard let next = pending.popFirst() else { return }
                inflight += 1
                group.addTask {
                    guard let image = await HubIOSInstalledApps.iconImageIncludingStore(
                        for: next.bundleId,
                        displayName: next.displayName
                    ),
                          let prepared = image.hub_preparedLauncherIcon(),
                          let png = prepared.hub_pngData(maxPixelSide: 512)
                    else { return false }
                    HubIOSAppGroup.saveIcon(png, for: next.bundleId)
                    return true
                }
            }
            for _ in 0..<min(4, missing.count) { launchNext(&group) }
            while inflight > 0, let didSave = await group.next() {
                inflight -= 1
                if didSave { savedCount += 1 }
                launchNext(&group)
            }
            return savedCount
        }
        if saved > 0 {
            pages = HubIOSAppGroup.hydratedPages(from: pages)
            persist()
        }
    }

    func setSlot(
        page pageId: Int,
        index: Int,
        bundleIdentifier: String?,
        displayName: String?,
        familyTokenData: Data? = nil,
        iconPNG: Data? = nil,
        launchURLString: String? = nil,
        persistNow: Bool = true
    ) {
        guard (0..<9).contains(index) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        var updated = pages
        let previous = updated[pageIndex].slots[index].bundleIdentifier
        let cleanBundleId = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        // 图标只跟 bundle id 走：调用方给的 PNG（App Store artwork）优先。
        let storedPNG: Data? = {
            guard cleanBundleId != nil else { return nil }
            if let iconPNG, iconPNG.count >= 64 { return iconPNG }
            return cleanBundleId.flatMap { HubIOSAppGroup.loadIconRaw(for: $0) }
        }()
        updated[pageIndex].slots[index] = HubSlotConfig(
            id: index,
            kind: .app,
            bundleIdentifier: cleanBundleId,
            displayName: displayName,
            iconPNG: storedPNG,
            familyTokenData: familyTokenData
        )
        if let storedPNG, let cleanBundleId {
            HubIOSAppGroup.saveIcon(storedPNG, pageId: pageId, slotId: index)
            HubIOSAppGroup.saveIcon(storedPNG, for: cleanBundleId)
        } else if let url = HubIOSAppGroup.iconFileURL(pageId: pageId, slotId: index) {
            try? FileManager.default.removeItem(at: url)
        }
        pages = updated
        if let cleanBundleId, let launchURLString, !launchURLString.isEmpty {
            HubIOSAppGroup.saveLaunchURL(launchURLString, for: cleanBundleId)
        }
        if persistNow {
            persist()
            if let previous, previous != bundleIdentifier {
                let stillUsed = pages.contains { page in
                    page.slots.contains { $0.bundleIdentifier == previous }
                }
                if !stillUsed {
                    HubIOSAppGroup.removeIcon(for: previous)
                }
            }
            if let cleanBundleId, launchURLString == nil || launchURLString?.isEmpty == true {
                Task.detached(priority: .utility) {
                    HubIOSInstalledApps.rememberLaunchURL(for: cleanBundleId)
                }
            }
            if cleanBundleId != nil {
                Task { await prefetchMissingIcons() }
            }
        }
    }

    /// 多选添加：全部写完只落盘 / 刷新小组件一次。
    func finishBatchUpdate() {
        persist()
        Task { await prefetchMissingIcons() }
    }

    func clearSlot(page pageId: Int, index: Int) {
        setSlot(page: pageId, index: index, bundleIdentifier: nil, displayName: nil)
    }

    func swapSlots(page pageA: Int, at i: Int, withPage pageB: Int, at j: Int) {
        guard (0..<9).contains(i), (0..<9).contains(j) else { return }
        if pageA == pageB, i == j { return }
        guard let indexA = pages.firstIndex(where: { $0.id == pageA }),
              let indexB = pages.firstIndex(where: { $0.id == pageB })
        else { return }

        var updated = pages
        if indexA == indexB {
            var next = updated[indexA].slots
            let a = next[i]
            let b = next[j]
            next[i] = remapped(b, id: i)
            next[j] = remapped(a, id: j)
            updated[indexA].slots = next
        } else {
            var slotsA = updated[indexA].slots
            var slotsB = updated[indexB].slots
            let a = slotsA[i]
            let b = slotsB[j]
            slotsA[i] = remapped(b, id: i)
            slotsB[j] = remapped(a, id: j)
            updated[indexA].slots = slotsA
            updated[indexB].slots = slotsB
        }
        pages = updated
        persist()
    }

    private func remapped(_ source: HubSlotConfig, id: Int) -> HubSlotConfig {
        HubSlotConfig(
            id: id,
            kind: .app,
            bundleIdentifier: source.bundleIdentifier,
            displayName: source.displayName,
            iconPNG: source.iconPNG,
            familyTokenData: source.familyTokenData
        )
    }

    private func persist() {
        HubIOSAppGroup.savePages(pages)
        let apps = HubIOSAppGroup.buildWidgetApps(from: pages)
        HubIOSAppGroup.saveWidgetSnapshot(apps: apps)
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
    }

    /// 主应用蜂巢缩放 / 平移结束后同步给小组件作为默认视口。
    func syncViewportToWidget(scale: CGFloat, offset: CGSize, baseIconSide: CGFloat) {
        HubIOSAppGroup.setWidgetViewport(scale: scale, offset: offset, baseIconSide: baseIconSide)
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
    }

    private static let frequentPriority: [String] = [
        "com.tencent.xin",
        "com.alipay.iphoneclient",
        "com.ss.iphone.ugc.Aweme",
        "com.tencent.mqq",
        "com.xingin.discover",
        "com.laiwang.DingTalk",
        "com.taobao.taobao4iphone",
        "com.apple.MobileSMS",
        "com.apple.mobilesafari",
        "com.apple.camera",
        "com.apple.mobilephone",
        "com.apple.mobileslideshow",
        "com.meituan.imeituan",
        "com.autonavi.amap",
        "com.xunmeng.pinduoduo",
        "com.netease.cloudmusic",
        "com.apple.Maps",
        "com.apple.Music",
        "com.apple.mobilemail",
        "com.apple.mobilecal",
        "com.apple.mobilenotes",
        "com.xiaojukeji.didi",
        "com.apple.AppStore",
        "com.apple.weather",
        "com.apple.mobiletimer",
    ]

    private static func makeStarterPages(installed: [HubIOSInstalledApps.Record]) -> [HubPageConfig] {
        let byId = Dictionary(installed.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [HubIOSInstalledApps.Record] = []
        var seen = Set<String>()
        for bundleId in frequentPriority {
            guard let record = byId[bundleId], seen.insert(bundleId).inserted else { continue }
            ordered.append(record)
        }
        for record in installed where seen.insert(record.bundleIdentifier).inserted {
            ordered.append(record)
        }

        var slots = (0..<9).map { HubSlotConfig(id: $0) }
        var filled = 0
        for record in ordered.prefix(9) {
            let png = HubIOSInstalledApps.iconPNG(for: record.bundleIdentifier)
            slots[filled] = HubSlotConfig(
                id: filled,
                kind: .app,
                bundleIdentifier: record.bundleIdentifier,
                displayName: record.displayName,
                iconPNG: png
            )
            filled += 1
        }
        return normalizePages([HubPageConfig(id: 0, title: "Phone", slots: slots)])
    }

    private static func normalizePages(_ pages: [HubPageConfig]) -> [HubPageConfig] {
        let sorted = pages.sorted { $0.id < $1.id }
        var normalized = Array(sorted.prefix(HubService.maxTabs))
        while normalized.count < HubService.maxTabs {
            let nextId = (normalized.map(\.id).max() ?? -1) + 1
            normalized.append(HubPageConfig(id: nextId, title: "Phone"))
        }
        return normalized.enumerated().map { index, page in
            HubPageConfig(id: page.id, title: index == 0 ? "Phone" : "Phone\(index)", slots: page.slots)
        }
    }
}
#endif
