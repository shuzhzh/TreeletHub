import AppKit
import Combine
import Foundation
import IOKit.ps

enum HubMacBatteryStatus {
    struct Snapshot: Equatable {
        var percent: Int?
        var isCharging: Bool
        /// 已接电源（含充满后不再充电）。
        var isPluggedIn: Bool
    }

    /// 笔记本或可充电设备上的电量；台式机通常无电池数据。
    static func currentSnapshot() -> Snapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return Snapshot(percent: nil, isCharging: false, isPluggedIn: false)
        }

        let descriptions: [[String: Any]] = list.compactMap { src in
            IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any]
        }

        // 优先内置电池；否则退回第一个在位电源。
        let desc = descriptions.first(where: { isInternalBattery($0) })
            ?? descriptions.first(where: { ($0[kIOPSIsPresentKey as String] as? Bool) == true })
            ?? descriptions.first

        guard let desc else {
            return Snapshot(percent: nil, isCharging: false, isPluggedIn: false)
        }

        let percent = normalizedPercent(from: desc)
        let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) == true
        let state = desc[kIOPSPowerSourceStateKey as String] as? String
        let isPluggedIn = state == (kIOPSACPowerValue as String) || isCharging
        return Snapshot(percent: percent, isCharging: isCharging, isPluggedIn: isPluggedIn)
    }

    private static func isInternalBattery(_ desc: [String: Any]) -> Bool {
        let transport = desc[kIOPSTransportTypeKey as String] as? String
        let type = desc[kIOPSTypeKey as String] as? String
        return transport == (kIOPSInternalType as String)
            || type == (kIOPSInternalBatteryType as String)
    }

    private static func normalizedPercent(from desc: [String: Any]) -> Int? {
        // IOKit 可能返回 Int / Double / CFNumber；统一转成 Double 再算。
        guard let current = numberValue(desc[kIOPSCurrentCapacityKey as String]) else { return nil }
        let maxCapacity = numberValue(desc[kIOPSMaxCapacityKey as String]) ?? 100
        guard maxCapacity > 0 else { return nil }
        let raw = (current / maxCapacity) * 100
        return min(100, max(0, Int(raw.rounded())))
    }

    private static func numberValue(_ any: Any?) -> Double? {
        switch any {
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as Int: return Double(v)
        case let v as Int64: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }
}

/// 稳定持有刷新订阅，避免 SwiftUI `body` 重绘时重建 `Timer.publish` 导致电量永不更新。
/// （灵动岛时钟每秒 `@Published`，会不断取消内联 60s Timer。）
@MainActor
final class HubMacBatteryMonitor: ObservableObject {
    @Published private(set) var snapshot: HubMacBatteryStatus.Snapshot

    private var poll: AnyCancellable?
    private var lifecycleBags = Set<AnyCancellable>()

    init() {
        snapshot = HubMacBatteryStatus.currentSnapshot()
        start()
    }

    func refresh() {
        let next = HubMacBatteryStatus.currentSnapshot()
        if next != snapshot {
            snapshot = next
        }
    }

    private func start() {
        poll = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &lifecycleBags)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &lifecycleBags)
    }
}
