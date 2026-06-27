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

/// 优先通过系统 `MediaRemote` 读取全局「正在播放」（抖音、浏览器、Spotify 等）；若无会话则回退到 AppleScript 读「音乐」。
@MainActor
final class HubIslandPlaybackState: ObservableObject {
    /// 当前所有占用音频的 App（来自 Core Audio 进程列表 + 必要时补充「音乐」）。
    @Published private(set) var audioOccupants: [HubIslandAudioOccupant] = []

    @Published private(set) var trackTitle: String = ""
    @Published private(set) var trackArtist: String = ""
    @Published private(set) var artworkImage: NSImage?
    /// 无封面时的播放源 App 图标（如抖音）。
    @Published private(set) var sourceAppIcon: NSImage?
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentFormatted: String = "0:00"
    @Published private(set) var durationFormatted: String = "--:--"
    @Published private(set) var isPlaying: Bool = false
    /// 当前详情来自「音乐」脚本（用于脚注文案）。
    @Published private(set) var hasNowPlayingFromMusic: Bool = false
    /// 当前详情来自系统媒体会话（MediaRemote）。
    @Published private(set) var hasNowPlayingFromSystem: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    /// HAL 多路输出时优先沿用上次与控制中心一致的媒体进程（避免点到灵动岛后前台变成自己而误选音效 App）。
    private var stickyMediaPID: pid_t = 0

    init() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let effectiveFrontPID: pid_t = frontPID == selfPID ? 0 : frontPID

            async let sysSnap = Task.detached {
                HubIslandMediaRemote.fetchSnapshot()
            }.value
            async let mrIdentity = Task.detached {
                HubIslandMediaRemote.fetchNowPlayingIdentity()
            }.value
            async let musicRow = Task.detached {
                HubIslandPlaybackState.runOsascriptQuery()
            }.value
            async let halTask = Task.detached {
                HubIslandAudioProcessMonitor.fetchRows()
            }.value

            let (snap, mrIdent, music, halRowsRaw) = await (sysSnap, mrIdentity, musicRow, halTask)
            guard !Task.isCancelled else { return }

            let halRows = halRowsRaw.filter { row in
                guard row.pid != selfPID else { return false }
                guard let app = NSRunningApplication(processIdentifier: row.pid) else { return false }
                switch app.activationPolicy {
                case .regular, .accessory: return true
                default: return false
                }
            }

            let (mrPidFallback, mrPlayingFallback) = mrIdent
            let mergedPID: pid_t = {
                if let s = snap, s.pid > 0 { return s.pid }
                return mrPidFallback
            }()

            let mergedSnap: HubIslandMediaRemote.Snapshot? = {
                if let s = snap {
                    let pid = mergedPID > 0 ? mergedPID : s.pid
                    return HubIslandMediaRemote.Snapshot(
                        title: s.title,
                        artist: s.artist,
                        duration: s.duration,
                        elapsed: s.elapsed,
                        isPlaying: s.isPlaying,
                        pid: pid,
                        artworkData: s.artworkData
                    )
                }
                guard mrPidFallback > 0 else { return nil }
                return HubIslandMediaRemote.Snapshot(
                    title: nil,
                    artist: nil,
                    duration: 0,
                    elapsed: 0,
                    isPlaying: mrPlayingFallback,
                    pid: mrPidFallback,
                    artworkData: nil
                )
            }()

            let halPick = HubIslandAudioProcessMonitor.pick(
                rows: halRows,
                frontmostPID: effectiveFrontPID,
                mrPID: mergedPID,
                stickyPID: stickyMediaPID
            )

            if let ms = mergedSnap, ms.looksLikeActiveSession {
                applySystemMedia(ms, musicRowIfSameSource: music, halRows: halRows, halPick: halPick)
                if ms.pid > 0 {
                    stickyMediaPID = ms.pid
                }
            } else if let pick = halPick {
                applyAudioProcessPick(pick)
                stickyMediaPID = pick.pid
            } else if let music {
                applyMusicScript(music)
                stickyMediaPID = 0
            } else {
                applyEmpty()
                stickyMediaPID = 0
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
        sourceAppIcon = nil
        progress = 0
        currentFormatted = "0:00"
        durationFormatted = "--:--"
        isPlaying = false
    }

    /// 与控制中心对齐播放键：MediaRemote 的 PID 可能与实际出声进程不一致，按 **bundle** 在 HAL 里查找是否在 `isRunningOutput`。
    private func resolvePlayingStateFromHAL(
        mediaPrimaryPID: pid_t,
        bundleID: String?,
        halRows: [HubIslandAudioProcessMonitor.Row],
        halPick: HubIslandAudioProcessMonitor.Pick?
    ) {
        if let bid = bundleID {
            var sawSameBundle = false
            var anyOutput = false
            for row in halRows {
                guard let rb = NSRunningApplication(processIdentifier: row.pid)?.bundleIdentifier, rb == bid else {
                    continue
                }
                sawSameBundle = true
                if row.isRunningOutput {
                    anyOutput = true
                }
            }
            if sawSameBundle {
                isPlaying = anyOutput
                return
            }
        }
        if let hal = halPick, hal.pid == mediaPrimaryPID {
            isPlaying = hal.isAudibleOutput
        }
    }

    private func applyMusicScript(_ info: HubIslandMusicScriptRow) {
        hasNowPlayingFromMusic = true
        hasNowPlayingFromSystem = false
        stickyMediaPID = 0
        trackTitle = info.title
        trackArtist = info.artist
        artworkImage = nil
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
    }

    private func applySystemMedia(
        _ snap: HubIslandMediaRemote.Snapshot,
        musicRowIfSameSource: HubIslandMusicScriptRow?,
        halRows: [HubIslandAudioProcessMonitor.Row],
        halPick: HubIslandAudioProcessMonitor.Pick?
    ) {
        hasNowPlayingFromMusic = false
        hasNowPlayingFromSystem = true

        let appFromPID: NSRunningApplication? =
            snap.pid > 0 ? NSRunningApplication(processIdentifier: snap.pid) : nil
        let appName = appFromPID?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleID = appFromPID?.bundleIdentifier

        let rawTitle = snap.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawArtist = snap.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if rawTitle.isEmpty {
            trackTitle = appName.isEmpty
                ? HubMacL10n.string("mac.playback.now_playing_title")
                : String(format: HubMacL10n.string("mac.playback.now_playing_with_app"), appName)
        } else {
            trackTitle = rawTitle
        }

        if !rawArtist.isEmpty {
            trackArtist = rawArtist
        } else if !appName.isEmpty, !rawTitle.isEmpty {
            trackArtist = appName
        } else {
            trackArtist = ""
        }

        if let data = snap.artworkData, let img = NSImage(data: data), img.isValid {
            artworkImage = img
            sourceAppIcon = appFromPID?.icon ?? Self.iconForBundleID(bundleID)
        } else {
            artworkImage = nil
            sourceAppIcon = appFromPID?.icon ?? Self.iconForBundleID(bundleID)
        }

        isPlaying = snap.isPlaying
        resolvePlayingStateFromHAL(
            mediaPrimaryPID: snap.pid,
            bundleID: bundleID,
            halRows: halRows,
            halPick: halPick
        )

        let duration = snap.duration
        let elapsed = snap.elapsed

        if duration > 0.5 {
            progress = min(1, max(0, elapsed / duration))
            durationFormatted = Self.formatTime(duration)
            currentFormatted = Self.formatTime(elapsed)
        } else {
            progress = 0
            durationFormatted = "--:--"
            currentFormatted = elapsed > 0 ? Self.formatTime(elapsed) : "0:00"
        }

        // 「音乐」若同时向 MediaRemote 汇报，可用脚本补齐缺失的时长与进度。
        if bundleID == "com.apple.Music", let m = musicRowIfSameSource, m.duration > 0 {
            progress = min(1, max(0, m.position / m.duration))
            durationFormatted = Self.formatTime(m.duration)
            currentFormatted = Self.formatTime(m.position)
            hasNowPlayingFromMusic = true
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
        sourceAppIcon = app.icon ?? Self.iconForBundleID(app.bundleIdentifier)

        isPlaying = pick.isAudibleOutput

        progress = 0
        currentFormatted = "0:00"
        durationFormatted = "--:--"
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
        let source = """
        tell application "System Events"
            set musicRunning to (exists process "Music")
        end tell
        if musicRunning is false then return ""
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
        guard let raw = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

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
