import CoreAudio
import Foundation

/// 使用 HAL 的音频进程列表（macOS 14.2+，公开 API），识别「谁在占用输出设备 / 是否正在输出音频」。
enum HubIslandAudioProcessMonitor: Sendable {
    struct Row: Sendable {
        let pid: pid_t
        let isRunningOutput: Bool
        let isRunningAny: Bool
    }

    /// 用于 UI：选一个前台相关的音频占用进程；`isAudibleOutput == true` 表示正在输出音频（应显示暂停键）。
    struct Pick: Sendable {
        let pid: pid_t
        let isAudibleOutput: Bool
    }

    /// 仅命中 CoreAudio，不涉及 AppKit（可在任意线程调用）。
    nonisolated static func fetchRows() -> [Row] {
        guard #available(macOS 14.2, *) else { return [] }

        let ids = processObjectIDs()
        guard !ids.isEmpty else { return [] }

        var rows: [Row] = []
        rows.reserveCapacity(ids.count)

        for oid in ids {
            guard let pid = readPID(objectID: oid), pid > 0 else { continue }
            let out = readUInt32(objectID: oid, selector: kAudioProcessPropertyIsRunningOutput) != 0
            let any = readUInt32(objectID: oid, selector: kAudioProcessPropertyIsRunning) != 0
            rows.append(Row(pid: pid, isRunningOutput: out, isRunningAny: any))
        }
        return rows
    }

    nonisolated static func pick(
        rows: [Row],
        frontmostPID: pid_t,
        stickyPID: pid_t
    ) -> Pick? {
        let outputting = rows.filter(\.isRunningOutput)
        if let r = choose(from: outputting, frontmostPID: frontmostPID, stickyPID: stickyPID) {
            return Pick(pid: r.pid, isAudibleOutput: true)
        }
        let pausedGraph = rows.filter { $0.isRunningAny && !$0.isRunningOutput }
        if let r = choose(from: pausedGraph, frontmostPID: frontmostPID, stickyPID: stickyPID) {
            return Pick(pid: r.pid, isAudibleOutput: false)
        }
        return nil
    }

    nonisolated private static func choose(
        from rows: [Row],
        frontmostPID: pid_t,
        stickyPID: pid_t
    ) -> Row? {
        guard !rows.isEmpty else { return nil }

        let pool = rows

        if stickyPID > 0, let r = pool.first(where: { $0.pid == stickyPID }) { return r }
        if frontmostPID > 0, let r = pool.first(where: { $0.pid == frontmostPID }) { return r }

        if pool.count == 1 { return pool.first }
        return pool.max(by: { $0.pid < $1.pid })
    }

    @available(macOS 14.2, *)
    nonisolated private static func processObjectIDs() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectHasProperty(sys, &addr) else { return [] }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &dataSize) == noErr,
              dataSize >= UInt32(MemoryLayout<AudioObjectID>.size)
        else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var buffer = [AudioObjectID](repeating: 0, count: count)
        var mutableSize = dataSize
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &mutableSize, &buffer) == noErr else {
            return []
        }
        return buffer.filter { $0 != kAudioObjectUnknown && $0 != 0 }
    }

    nonisolated private static func readPID(objectID: AudioObjectID) -> pid_t? {
        guard let u = readUInt32(objectID: objectID, selector: kAudioProcessPropertyPID), u > 0 else {
            return nil
        }
        return pid_t(u)
    }

    nonisolated private static func readUInt32(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }
}
