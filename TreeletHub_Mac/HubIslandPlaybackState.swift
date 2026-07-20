import AppKit
import Combine
import Foundation

/// HAL 中占用音频设备的 App（展示用；图标在界面层按 pid 读取）。
struct HubIslandAudioOccupant: Identifiable, Equatable {
    let pid: pid_t
    var id: pid_t { pid }
    let displayName: String
    /// `kAudioProcessPropertyIsRunningOutput`：正在向设备输出音频。
    let isAudibleOutput: Bool
    /// `kAudioProcessPropertyIsRunning`：仍占用音频图（含暂停等）。
    let hasAudioGraph: Bool
}

/// 「正在播放」数据中枢（仅使用公开 API，可上架 Mac App Store）：
/// 1. AppleScript 读「音乐」App（scripting-targets 授权）：曲目 / 艺人 / 进度 / 封面；
/// 2. Core Audio HAL 进程列表（macOS 14.2+）：其他 App 只展示图标与「正在输出 / 占用」状态。
@MainActor
final class HubIslandPlaybackState: ObservableObject {
    /// 当前所有占用音频的 App（来自 Core Audio 进程列表 + 必要时补充「音乐」）。
    @Published private(set) var audioOccupants: [HubIslandAudioOccupant] = []

    @Published private(set) var trackTitle: String = ""
    @Published private(set) var trackArtist: String = ""
    @Published private(set) var artworkImage: NSImage?
    /// 无封面时的播放源 App 图标。
    @Published private(set) var sourceAppIcon: NSImage?
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentFormatted: String = "0:00"
    @Published private(set) var durationFormatted: String = "--:--"
    @Published private(set) var isPlaying: Bool = false
    /// 当前详情来自「音乐」脚本（含完整曲目信息）。
    @Published private(set) var hasNowPlayingFromMusic: Bool = false
    /// 当前详情来自 HAL 音频进程（仅 App 级信息，无曲目元数据）。
    @Published private(set) var hasNowPlayingFromSystem: Bool = false
    private var pollTimer: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var pollInterval: TimeInterval = 1.0
    /// HAL 多路输出时优先沿用上次选中的媒体进程（避免点到灵动岛后前台变成自己而误选音效 App）。
    private var stickyMediaPID: pid_t = 0
    /// 当前已取到封面的曲目标识（标题|艺人）；切歌时才重新取封面。
    private var musicArtworkTrackKey: String?
    private var artworkFetchTask: Task<Void, Never>?

    init() {
        startPolling(every: pollInterval)
        refresh()
    }

    /// 按灵动岛形态调整轮询频率：展开 1s、收起 2s、贴边 6s。
    func setPollingInterval(_ interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        startPolling(every: interval)
    }

    private func startPolling(every interval: TimeInterval) {
        pollTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let effectiveFrontPID: pid_t = frontPID == selfPID ? 0 : frontPID

            // 「音乐」未运行时直接跳过 AppleScript，避免每次轮询都 fork `osascript`。
            let musicIsRunning = !NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
            async let musicRow = Task.detached { () -> HubIslandMusicScriptRow? in
                guard musicIsRunning else { return nil }
                return HubIslandPlaybackState.runOsascriptQuery()
            }.value
            async let halTask = Task.detached {
                HubIslandAudioProcessMonitor.fetchRows()
            }.value

            let (music, halRowsRaw) = await (musicRow, halTask)
            guard !Task.isCancelled else { return }

            let halRows = Self.resolveDisplayableRows(halRowsRaw, selfPID: selfPID)

            let halPick = HubIslandAudioProcessMonitor.pick(
                rows: halRows,
                frontmostPID: effectiveFrontPID,
                stickyPID: stickyMediaPID
            )

            // 优先级：正在播放的「音乐」> 正在出声的其他 App > 暂停的「音乐」> 占用音频的 App。
            if let music, music.isPlaying {
                applyMusicScript(music)
            } else if let pick = halPick, pick.isAudibleOutput {
                applyAudioProcessPick(pick)
                stickyMediaPID = pick.pid
            } else if let music {
                applyMusicScript(music)
            } else if let pick = halPick {
                applyAudioProcessPick(pick)
                stickyMediaPID = pick.pid
            } else {
                applyEmpty()
            }

            rebuildAudioOccupants(from: halRows)
        }
    }

    /// 收起态「播放」摘要：多 App 并列；无占用列表时退回单曲目标题。
    var collapsedPlaybackSubtitle: String {
        if !audioOccupants.isEmpty {
            let parts = audioOccupants.map { occ in
                occ.isAudibleOutput
                    ? String(format: HubMacL10n.string("mac.playback.audible_suffix"), occ.displayName)
                    : occ.displayName
            }
            let joined = parts.joined(separator: "、")
            let capped = joined.count > 36 ? String(joined.prefix(33)) + "…" : joined
            return "♪ \(capped)"
        }
        if hasNowPlayingFromMusic || hasNowPlayingFromSystem {
            let t = trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            let short = t.count > 26 ? String(t.prefix(26)) + "…" : t
            return "♪ \(short)"
        }
        return ""
    }

    private func rebuildAudioOccupants(from halRows: [HubIslandAudioProcessMonitor.Row]) {
        var seen = Set<pid_t>()
        var list: [HubIslandAudioOccupant] = []

        for row in halRows where row.isRunningAny {
            guard !seen.contains(row.pid) else { continue }
            guard let app = NSRunningApplication(processIdentifier: row.pid) else { continue }
            seen.insert(row.pid)
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? String(format: HubMacL10n.string("mac.playback.process_fallback"), row.pid)
            list.append(
                HubIslandAudioOccupant(
                    pid: row.pid,
                    displayName: name,
                    isAudibleOutput: row.isRunningOutput,
                    hasAudioGraph: row.isRunningAny
                )
            )
        }

        if hasNowPlayingFromMusic {
            let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            for app in musicApps {
                let pid = app.processIdentifier
                guard !seen.contains(pid) else { continue }
                seen.insert(pid)
                let name = app.localizedName ?? HubMacL10n.string("mac.playback.music_fallback")
                list.append(
                    HubIslandAudioOccupant(
                        pid: pid,
                        displayName: name,
                        isAudibleOutput: isPlaying,
                        hasAudioGraph: true
                    )
                )
            }
        }

        list.sort {
            if $0.isAudibleOutput != $1.isAudibleOutput { return $0.isAudibleOutput && !$1.isAudibleOutput }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        audioOccupants = list
    }

    private func applyEmpty() {
        hasNowPlayingFromMusic = false
        hasNowPlayingFromSystem = false
        stickyMediaPID = 0
        trackTitle = ""
        trackArtist = ""
        artworkImage = nil
        musicArtworkTrackKey = nil
        sourceAppIcon = nil
        progress = 0
        currentFormatted = "0:00"
        durationFormatted = "--:--"
        isPlaying = false
    }

    private func applyMusicScript(_ info: HubIslandMusicScriptRow) {
        hasNowPlayingFromMusic = true
        hasNowPlayingFromSystem = false
        stickyMediaPID = 0
        trackTitle = info.title
        trackArtist = info.artist
        sourceAppIcon = Self.iconForBundleID("com.apple.Music")
        isPlaying = info.isPlaying

        if info.duration > 0 {
            progress = min(1, max(0, info.position / info.duration))
            durationFormatted = Self.formatTime(info.duration)
            currentFormatted = Self.formatTime(info.position)
        } else {
            progress = 0
            durationFormatted = "--:--"
            currentFormatted = Self.formatTime(max(0, info.position))
        }

        // 封面只在切歌时取一次（AppleScript 传输较重，不进轮询热路径）。
        let trackKey = "\(info.title)|\(info.artist)"
        if trackKey != musicArtworkTrackKey {
            musicArtworkTrackKey = trackKey
            artworkImage = nil
            fetchMusicArtwork(trackKey: trackKey)
        }
    }

    private func fetchMusicArtwork(trackKey: String) {
        artworkFetchTask?.cancel()
        artworkFetchTask = Task { @MainActor [weak self] in
            let data = await Task.detached {
                HubIslandPlaybackState.runOsascriptArtworkQuery()
            }.value
            guard let self, !Task.isCancelled else { return }
            // 取回时可能已经切歌 / 切换到其他数据源，丢弃过期结果。
            guard self.hasNowPlayingFromMusic, self.musicArtworkTrackKey == trackKey else { return }
            if let data, let img = NSImage(data: data), img.isValid {
                self.artworkImage = img
            }
        }
    }

    private func applyAudioProcessPick(_ pick: HubIslandAudioProcessMonitor.Pick) {
        hasNowPlayingFromMusic = false
        hasNowPlayingFromSystem = true

        guard let app = NSRunningApplication(processIdentifier: pick.pid) else {
            applyEmpty()
            return
        }

        let trimmedName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmedName.isEmpty ? HubMacL10n.string("mac.playback.audio_generic") : trimmedName
        trackTitle = name
        trackArtist = pick.isAudibleOutput
            ? HubMacL10n.string("mac.playback.artist_output")
            : HubMacL10n.string("mac.playback.artist_idle")

        artworkImage = nil
        musicArtworkTrackKey = nil
        sourceAppIcon = app.icon ?? Self.iconForBundleID(app.bundleIdentifier)

        isPlaying = pick.isAudibleOutput

        progress = 0
        currentFormatted = "0:00"
        durationFormatted = "--:--"
    }

    /// HAL 返回的常是 Helper / 渲染子进程（Chrome、抖音等实际出声的进程），
    /// 它们不是 GUI 应用、拿不到 `NSRunningApplication`。沿父进程链向上找到
    /// 第一个常规 App，并把同一宿主的多条子进程记录归并（输出状态取或）。
    nonisolated private static func resolveDisplayableRows(
        _ rows: [HubIslandAudioProcessMonitor.Row],
        selfPID: pid_t
    ) -> [HubIslandAudioProcessMonitor.Row] {
        var merged: [pid_t: (output: Bool, any: Bool)] = [:]
        var order: [pid_t] = []
        for row in rows {
            guard let appPID = displayableAppPID(for: row.pid, selfPID: selfPID) else { continue }
            if merged[appPID] == nil { order.append(appPID) }
            let current = merged[appPID] ?? (false, false)
            merged[appPID] = (current.output || row.isRunningOutput, current.any || row.isRunningAny)
        }
        return order.compactMap { pid in
            guard let flags = merged[pid] else { return nil }
            return HubIslandAudioProcessMonitor.Row(pid: pid, isRunningOutput: flags.output, isRunningAny: flags.any)
        }
    }

    /// 自身及祖先里第一个 `.regular` / `.accessory` 的 App 进程；到 launchd（pid 1）为止。
    nonisolated private static func displayableAppPID(for pid: pid_t, selfPID: pid_t) -> pid_t? {
        var current = pid
        for _ in 0..<8 {
            guard current > 1, current != selfPID else { return nil }
            if let app = NSRunningApplication(processIdentifier: current) {
                switch app.activationPolicy {
                case .regular, .accessory: return current
                default: break
                }
            }
            guard let parent = parentPID(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    /// 通过 `sysctl`（公开 API，沙盒可用）读取父进程 PID。
    nonisolated private static func parentPID(of pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let status = mib.withUnsafeMutableBufferPointer { ptr in
            sysctl(ptr.baseAddress, 4, &info, &size, nil, 0)
        }
        guard status == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    private static func iconForBundleID(_ bundleID: String?) -> NSImage? {
        guard let bid = bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// 与 MainActor 隔离无关；仅在后台线程跑 `osascript`，避免阻塞 UI。
    nonisolated private static func runOsascriptQuery() -> HubIslandMusicScriptRow? {
        // 调用方已确认「音乐」在运行；不再借道 System Events 判断（减少一个自动化目标）。
        let source = """
        tell application "Music"
            try
                if not (exists current track) then return ""
                set stateStr to player state as string
                set t to name of current track
                set ar to artist of current track
                set pos to player position
                set dur to duration of current track
                return stateStr & "|||" & t & "|||" & ar & "|||" & pos & "|||" & dur
            on error
                return ""
            end try
        end tell
        """

        guard let raw = runOsascript(source), !raw.isEmpty else { return nil }

        let parts = raw.components(separatedBy: "|||")
        guard parts.count == 5 else { return nil }

        let stateStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = parts[1]
        let artist = parts[2]
        let posStr = parts[3].replacingOccurrences(of: ",", with: ".")
        let durStr = parts[4].replacingOccurrences(of: ",", with: ".")

        guard let position = Double(posStr), let duration = Double(durStr) else { return nil }

        let playing = stateStr == "playing"
        return HubIslandMusicScriptRow(
            title: title,
            artist: artist,
            position: position,
            duration: duration,
            isPlaying: playing
        )
    }

    /// 读取「音乐」当前曲目的封面（仅在切歌时调用一次）。
    /// `osascript` 会把二进制输出为 `«data tdtaFFD8…»` 形式的十六进制字面量。
    nonisolated private static func runOsascriptArtworkQuery() -> Data? {
        let source = """
        tell application "Music"
            try
                if not (exists current track) then return ""
                if (count of artworks of current track) is 0 then return ""
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """

        guard let raw = runOsascript(source), !raw.isEmpty else { return nil }
        return decodeAppleScriptDataLiteral(raw)
    }

    /// 解析 AppleScript 的 `«data XXXX48656C6C6F…»` 字面量：跳过 4 字符类型码后十六进制解码。
    nonisolated private static func decodeAppleScriptDataLiteral(_ raw: String) -> Data? {
        guard let start = raw.range(of: "«data "),
              let end = raw.range(of: "»", range: start.upperBound..<raw.endIndex)
        else { return nil }
        var hex = String(raw[start.upperBound..<end.lowerBound])
        hex = hex.filter { !$0.isWhitespace }
        guard hex.count > 4 else { return nil }
        hex.removeFirst(4)
        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    nonisolated private static func runOsascript(_ source: String) -> String? {
        guard let scriptData = source.data(using: .utf8) else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "AppleScript", "-"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
        } catch {
            return nil
        }

        stdinPipe.fileHandleForWriting.write(scriptData)
        try? stdinPipe.fileHandleForWriting.close()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { return nil }
        return String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HubIslandMusicScriptRow: Sendable {
    let title: String
    let artist: String
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
