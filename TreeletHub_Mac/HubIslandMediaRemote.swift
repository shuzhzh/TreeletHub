import Foundation

// 文件级常量：`nonisolated(unsafe)` 供 `nonisolated static` 读取，避免被默认推断为 MainActor 隔离。
private nonisolated(unsafe) let kMRNowPlayingTitle = "kMRMediaRemoteNowPlayingInfoTitle"
private nonisolated(unsafe) let kMRNowPlayingArtist = "kMRMediaRemoteNowPlayingInfoArtist"
private nonisolated(unsafe) let kMRNowPlayingDuration = "kMRMediaRemoteNowPlayingInfoDuration"
private nonisolated(unsafe) let kMRNowPlayingElapsed = "kMRMediaRemoteNowPlayingInfoElapsedTime"
private nonisolated(unsafe) let kMRNowPlayingPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
private nonisolated(unsafe) let kMRNowPlayingArtwork = "kMRMediaRemoteNowPlayingInfoArtworkData"

/// 动态加载系统 `MediaRemote`（私有框架），读取控制中心同源的「正在播放」信息。
/// 用于抖音、浏览器、Spotify 等非「音乐」App；上架审核风险需自行评估。
enum HubIslandMediaRemote: Sendable {
    struct Snapshot: Sendable {
        var title: String?
        var artist: String?
        var duration: TimeInterval
        var elapsed: TimeInterval
        var isPlaying: Bool
        var pid: pid_t
        var artworkData: Data?

        /// 是否与当前媒体会话有足够关联（避免残留空字典误判）。
        var looksLikeActiveSession: Bool {
            if pid > 0 { return true }
            if isPlaying { return true }
            let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return true }
            if duration > 0.5 || elapsed > 0.5 { return true }
            return artworkData != nil
        }
    }

    /// 在后台线程调用；若框架或符号不可用则返回 `nil`。
    nonisolated static func fetchSnapshot() -> Snapshot? {
        guard
            let bundle = CFBundleCreate(kCFAllocatorDefault, cfMediaRemoteURL()),
            let ptrInfo = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
            let ptrPlaying = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString),
            let ptrPID = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString)
        else {
            return nil
        }

        typealias InfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
        typealias PlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
        typealias PIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

        let MRGetNowPlayingInfo = unsafeBitCast(ptrInfo, to: InfoFn.self)
        let MRGetIsPlaying = unsafeBitCast(ptrPlaying, to: PlayingFn.self)
        let MRGetPID = unsafeBitCast(ptrPID, to: PIDFn.self)

        var dict: [String: Any]?
        var playing = false
        var pid: pid_t = 0

        let group = DispatchGroup()
        let bg = DispatchQueue.global(qos: .utility)

        group.enter()
        MRGetNowPlayingInfo(bg) { raw in
            defer { group.leave() }
            guard let raw else { return }
            dict = raw as NSDictionary as? [String: Any]
        }

        group.enter()
        MRGetIsPlaying(bg) { flag in
            defer { group.leave() }
            playing = flag
        }

        group.enter()
        MRGetPID(bg) { rawPid in
            defer { group.leave() }
            pid = pid_t(rawPid)
        }

        let waitResult = group.wait(timeout: .now() + .milliseconds(2500))
        guard waitResult == .success else { return nil }

        guard let d = dict else {
            return Snapshot(title: nil, artist: nil, duration: 0, elapsed: 0, isPlaying: playing, pid: pid, artworkData: nil)
        }

        let title = string(for: kMRNowPlayingTitle, in: d)
        let artist = string(for: kMRNowPlayingArtist, in: d)

        let duration = double(for: kMRNowPlayingDuration, in: d) ?? 0
        let elapsed = double(for: kMRNowPlayingElapsed, in: d) ?? 0
        let rate = double(for: kMRNowPlayingPlaybackRate, in: d)

        let inferredPlaying: Bool
        if let rate {
            inferredPlaying = rate > 0.01
        } else {
            inferredPlaying = playing
        }

        let artworkBytes = d[kMRNowPlayingArtwork] as? Data ?? (d[kMRNowPlayingArtwork] as? NSData) as Data?

        return Snapshot(
            title: title,
            artist: artist,
            duration: max(0, duration),
            elapsed: max(0, elapsed),
            isPlaying: inferredPlaying,
            pid: pid,
            artworkData: artworkBytes
        )
    }

    /// 单独查询「当前接管媒体键」的进程 PID（与控制中心一致）；若整包 `fetchSnapshot` 超时失败，仍可用此值对齐展示。
    nonisolated static func fetchNowPlayingIdentity() -> (pid: pid_t, isPlaying: Bool) {
        guard
            let bundle = CFBundleCreate(kCFAllocatorDefault, cfMediaRemoteURL()),
            let ptrPlaying = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString),
            let ptrPID = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString)
        else {
            return (0, false)
        }

        typealias PlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
        typealias PIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

        let MRGetIsPlaying = unsafeBitCast(ptrPlaying, to: PlayingFn.self)
        let MRGetPID = unsafeBitCast(ptrPID, to: PIDFn.self)
        let bg = DispatchQueue.global(qos: .utility)

        var pid: pid_t = 0
        let semPid = DispatchSemaphore(value: 0)
        MRGetPID(bg) { raw in
            pid = pid_t(raw)
            semPid.signal()
        }
        _ = semPid.wait(timeout: .now() + .milliseconds(3200))

        var playing = false
        let semPlay = DispatchSemaphore(value: 0)
        MRGetIsPlaying(bg) { flag in
            playing = flag
            semPlay.signal()
        }
        _ = semPlay.wait(timeout: .now() + .milliseconds(3200))

        return (pid, playing)
    }

    nonisolated private static func cfMediaRemoteURL() -> CFURL {
        URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
    }

    nonisolated private static func string(for key: String, in dict: [String: Any]) -> String? {
        guard let v = dict[key] else { return nil }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let s = v as? NSString {
            let t = String(s).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    nonisolated private static func double(for key: String, in dict: [String: Any]) -> Double? {
        guard let v = dict[key] else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        return nil
    }
}
