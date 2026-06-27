import Foundation
import IOKit.ps

enum HubMacBatteryStatus {
    struct Snapshot {
        var percent: Int?
        var isCharging: Bool
    }

    /// 笔记本或可充电设备上的电量；台式机通常无电池数据。
    static func currentSnapshot() -> Snapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return Snapshot(percent: nil, isCharging: false)
        }

        let percent = desc[kIOPSCurrentCapacityKey as String] as? Int
        let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) == true
        return Snapshot(percent: percent, isCharging: isCharging)
    }
}
