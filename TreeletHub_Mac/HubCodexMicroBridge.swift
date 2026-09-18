import AppKit
import Combine
import Foundation

/// Bridges TreeletHub ↔ Codex on Mac via deep links + Codex CLI.
/// Does not use Accessibility, Input Monitoring, or key injection (App Store 2.4.5).
@MainActor
final class HubCodexMicroBridge: ObservableObject {
    private static let mappingDefaultsKeyPrefix = "treelethub.codexMicro.mapping."
    private static let targetDefaultsKey = "treelethub.codexMicro.controlTarget"
    /// Bump to force-reset pad layouts after removing non-functional GUI actions.
    private static let padLayoutEpochKey = "treelethub.codexMicro.padLayoutEpoch"
    private static let padLayoutEpoch = 3
    private static let doubleTapWindow: TimeInterval = 0.35
    private static let reasoningLevels = ["minimal", "low", "medium", "high", "xhigh"]

    @Published private(set) var state: HubCodexMicroState = .empty

    private static let minimumCommandInterval: TimeInterval = 0.25
    private static let burstLimit = 12
    private static let burstWindow: TimeInterval = 3.0

    private var pollTask: Task<Void, Never>?
    private var stateObservers: [() -> Void] = []
    private var lastAgentTapAt: [Int: Date] = [:]
    private var handsFreeRecording = false
    private var controlTarget: HubCodexControlTarget = .codex
    private var lastCommandAt: Date?
    private var recentCommandTimestamps: [Date] = []
    private var isPerformingCommand = false

    init() {
        controlTarget = Self.loadTarget()
        if !HubCodexControlTarget.padSupportedTargets.contains(controlTarget) {
            controlTarget = .codex
            Self.saveTarget(.codex)
        }
        state.mapping = Self.loadMapping(for: controlTarget)
        refreshState()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshState()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func onStateChange(_ handler: @escaping () -> Void) {
        stateObservers.append(handler)
    }

    func snapshotEnvelope() -> HubWireEnvelope {
        HubWireEnvelope(
            op: HubWireEnvelope.opCodexMicroState,
            message: HubCodexMicroWire.encodeState(state),
            agents: state.agents
        )
    }

    func handle(_ command: HubCodexMicroCommand) async throws {
        if Self.isPassiveCommand(command.kind) {
            try await handleInner(command)
            refreshState()
            return
        }

        let isPTTBegin = command.kind == HubCodexMicroCommand.kindCommand && command.action == .pushToTalk
        if command.kind == HubCodexMicroCommand.kindPushToTalkEnd
            || command.kind == HubCodexMicroCommand.kindInsertText
            || isPTTBegin
        {
            let deadline = Date().addingTimeInterval(1.0)
            while isPerformingCommand, Date() < deadline {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            try await handleInner(command)
            refreshState()
            return
        }

        guard !isPerformingCommand else { return }
        switch throttleDecision() {
        case .allow:
            break
        case .dropSilently:
            return
        case .reject(let message):
            state.lastControlError = message
            publish()
            return
        }

        isPerformingCommand = true
        defer { isPerformingCommand = false }
        noteCommandDispatched()

        state.lastControlError = nil
        do {
            try await handleInner(command)
            state.lastControlError = nil
        } catch {
            state.lastControlError = error.localizedDescription
            publish()
            throw error
        }
        refreshState()
    }

    private static func isPassiveCommand(_ kind: String) -> Bool {
        switch kind {
        case HubCodexMicroCommand.kindRequestState,
             HubCodexMicroCommand.kindSetMapping,
             HubCodexMicroCommand.kindSetTarget,
             HubCodexMicroCommand.kindLayerCycle,
             HubCodexMicroCommand.kindOpenAccessibilitySettings:
            return true
        default:
            return false
        }
    }

    private enum ThrottleDecision {
        case allow
        case dropSilently
        case reject(String)
    }

    private func throttleDecision() -> ThrottleDecision {
        let now = Date()
        if let last = lastCommandAt, now.timeIntervalSince(last) < Self.minimumCommandInterval {
            return .dropSilently
        }
        recentCommandTimestamps.removeAll { now.timeIntervalSince($0) > Self.burstWindow }
        if recentCommandTimestamps.count >= Self.burstLimit {
            return .reject("指令过于频繁，已暂停以保护 Codex")
        }
        return .allow
    }

    private func noteCommandDispatched() {
        let now = Date()
        lastCommandAt = now
        recentCommandTimestamps.append(now)
        recentCommandTimestamps.removeAll { now.timeIntervalSince($0) > Self.burstWindow }
    }

    private func handleInner(_ command: HubCodexMicroCommand) async throws {
        switch command.kind {
        case HubCodexMicroCommand.kindRequestState:
            refreshState()
        case HubCodexMicroCommand.kindSetMapping:
            if let mapping = command.mapping {
                applyMapping(mapping)
            }
        case HubCodexMicroCommand.kindSetTarget:
            guard let target = command.target else { return }
            setControlTarget(target)
        case HubCodexMicroCommand.kindOpenAccessibilitySettings:
            // Legacy op: open Codex settings / CLI docs instead of Accessibility.
            if HubCodexCLI.isCLIAvailable == false {
                NSWorkspace.shared.open(URL(string: "https://developers.openai.com/codex/cli")!)
            } else {
                try? await openCodexDeepLink("codex://settings")
            }
        case HubCodexMicroCommand.kindAgentTap:
            guard let index = command.agentIndex else { return }
            try await handleAgentTap(index: index, forceFront: false)
        case HubCodexMicroCommand.kindAgentDoubleTap:
            guard let index = command.agentIndex else { return }
            try await handleAgentTap(index: index, forceFront: true)
        case HubCodexMicroCommand.kindCommand:
            let action = command.action ?? .none
            try await perform(action, handsFree: command.handsFree == true)
        case HubCodexMicroCommand.kindJoystick:
            guard let direction = command.direction else { return }
            let key = direction.rawValue
            let action = state.mapping.joystick[key] ?? HubCodexMicroMapping.defaultJoystick[key] ?? .none
            try await perform(action)
        case HubCodexMicroCommand.kindDialTurn:
            let steps = command.steps ?? Int(command.agentIndex ?? 0)
            try await handleDialTurn(steps: steps == 0 ? 1 : steps)
        case HubCodexMicroCommand.kindDialPress:
            try await handleDialPress()
        case HubCodexMicroCommand.kindDialLongPress:
            try await perform(.openSettings)
        case HubCodexMicroCommand.kindDialCancel:
            state.dialCancelArmed = false
            publish()
        case HubCodexMicroCommand.kindLayerCycle:
            let next = (state.layer % 6) + 1
            state.layer = next
            publish()
        case HubCodexMicroCommand.kindPushToTalkEnd:
            try await endPushToTalk()
        case HubCodexMicroCommand.kindInsertText:
            guard let text = command.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return }
            try await insertTranscribedText(text)
        default:
            throw NSError(
                domain: "TreeletHub",
                code: 3100,
                userInfo: [NSLocalizedDescriptionKey: "未知 Codex Micro 指令"]
            )
        }
    }

    // MARK: - State

    private func refreshState() {
        let availability = HubCodexControlTarget.padSupportedTargets.map { target -> HubCodexTargetAvailability in
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) != nil
                || (target == .codex && HubCodexCLI.isCLIAvailable)
            let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == target.bundleIdentifier }
            return HubCodexTargetAvailability(target: target, installed: installed, running: running)
        }

        controlTarget = .codex
        let current = availability.first(where: { $0.target == .codex })
        let installed = current?.installed == true
        let running = current?.running == true
        let cliOK = HubCodexCLI.isCLIAvailable
        // Wire field kept for older clients: means “control path ready”, not macOS Accessibility.
        let controlReady = installed || cliOK

        var agents = readAgentsFromLocalState()
        if agents.allSatisfy({ $0.status == .unassigned }), running || cliOK {
            agents = heuristicAgentsWhileRunning(title: "Codex")
        }

        if let selected = state.selectedAgentIndex, agents.indices.contains(selected) {
            for i in agents.indices {
                agents[i].isSelected = (i == selected)
            }
        }

        state.agents = agents
        state.controlTarget = .codex
        state.targetInstalled = installed
        state.targetRunning = running
        state.targetDisplayName = HubCodexControlTarget.codex.displayNameEN
        state.chatGPTRunning = running
        state.chatGPTBundleId = HubCodexControlTarget.codex.bundleIdentifier
        state.accessibilityGranted = controlReady
        state.automationReady = controlReady
        state.availableTargets = availability
        state.updatedAt = Date().timeIntervalSince1970
        publish()
    }

    private func publish() {
        for observer in stateObservers {
            observer()
        }
    }

    private func applyMapping(_ mapping: HubCodexMicroMapping) {
        var normalized = mapping.sanitizedForCodexPad()
        if normalized.commandKeys.count != 6 {
            normalized.commandKeys = HubCodexMicroMapping.defaultCommandKeys(for: .codex)
        }
        if normalized.customAgentThreadIds.count != 6 {
            normalized.customAgentThreadIds = Array(repeating: nil, count: 6)
        }
        state.mapping = normalized
        Self.saveMapping(normalized, for: .codex)
        publish()
    }

    private func setControlTarget(_ target: HubCodexControlTarget) {
        // Only Codex is supported; ignore ChatGPT / Cursor requests from older clients.
        controlTarget = HubCodexControlTarget.padSupportedTargets.contains(target) ? target : .codex
        Self.saveTarget(controlTarget)
        state.controlTarget = controlTarget
        state.mapping = Self.loadMapping(for: controlTarget)
        state.lastControlError = nil
        refreshState()
    }

    private static func loadMapping(for target: HubCodexControlTarget) -> HubCodexMicroMapping {
        if UserDefaults.standard.integer(forKey: padLayoutEpochKey) < padLayoutEpoch {
            let fresh = HubCodexMicroMapping.default(for: .codex)
            saveMapping(fresh, for: .codex)
            UserDefaults.standard.set(padLayoutEpoch, forKey: padLayoutEpochKey)
            return fresh
        }

        let key = mappingDefaultsKeyPrefix + target.rawValue
        var mapping: HubCodexMicroMapping
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(HubCodexMicroMapping.self, from: data)
        {
            mapping = decoded
        } else if let data = UserDefaults.standard.data(forKey: "treelethub.codexMicro.mapping"),
                  let decoded = try? JSONDecoder().decode(HubCodexMicroMapping.self, from: data),
                  target == .codex
        {
            mapping = decoded
            saveMapping(mapping, for: target)
        } else {
            mapping = .default(for: target)
        }
        let sanitized = mapping.sanitizedForCodexPad()
        if sanitized != mapping {
            saveMapping(sanitized, for: target)
        }
        return sanitized
    }

    private static func saveMapping(_ mapping: HubCodexMicroMapping, for target: HubCodexControlTarget) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        UserDefaults.standard.set(data, forKey: mappingDefaultsKeyPrefix + target.rawValue)
    }

    private static func loadTarget() -> HubCodexControlTarget {
        if let raw = UserDefaults.standard.string(forKey: targetDefaultsKey),
           let target = HubCodexControlTarget(rawValue: raw),
           HubCodexControlTarget.padSupportedTargets.contains(target)
        {
            return target
        }
        return .codex
    }

    private static func saveTarget(_ target: HubCodexControlTarget) {
        UserDefaults.standard.set(target.rawValue, forKey: targetDefaultsKey)
    }

    // MARK: - Local Codex status (files under real ~/.codex)

    private func readAgentsFromLocalState() -> [HubCodexAgentSlot] {
        let unread = readUnreadThreadIds()
        let recent = readRecentThreadSummaries()
        let source = state.mapping.agentSource
        let dates = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0.modified) })

        var chosen: [(id: String, title: String)] = []
        switch source {
        case .mostRecent, .pinned:
            chosen = recent.prefix(6).map { ($0.id, $0.title) }
        case .priority:
            let mapped = recent.map { ($0.id, $0.title) }
            let priority = mapped.filter { unread.contains($0.0) } + mapped.filter { !unread.contains($0.0) }
            chosen = Array(priority.prefix(6))
        case .custom:
            for tid in state.mapping.customAgentThreadIds {
                if let tid, let hit = recent.first(where: { $0.id == tid }) {
                    chosen.append((hit.id, hit.title))
                } else if let tid {
                    chosen.append((tid, String(tid.prefix(8))))
                } else {
                    chosen.append(("", ""))
                }
            }
            while chosen.count < 6 { chosen.append(("", "")) }
            chosen = Array(chosen.prefix(6))
        }

        return (0..<6).map { index in
            guard chosen.indices.contains(index), !chosen[index].id.isEmpty else {
                return HubCodexAgentSlot(id: index, status: .unassigned)
            }
            let item = chosen[index]
            let status: HubCodexAgentStatus
            if unread.contains(item.id) {
                status = .complete
            } else if let mtime = dates[item.id], Date().timeIntervalSince(mtime) < 45 {
                status = .thinking
            } else {
                status = .idle
            }
            return HubCodexAgentSlot(
                id: index,
                status: status,
                title: item.title.isEmpty ? nil : item.title,
                threadId: item.id,
                isSelected: state.selectedAgentIndex == index
            )
        }
    }

    private func heuristicAgentsWhileRunning(title: String?) -> [HubCodexAgentSlot] {
        (0..<6).map { index in
            HubCodexAgentSlot(
                id: index,
                status: index == 0 ? .idle : .unassigned,
                title: index == 0 ? title : nil,
                isSelected: state.selectedAgentIndex == index
            )
        }
    }

    private func readUnreadThreadIds() -> Set<String> {
        let url = HubCodexCLI.codexHomeDirectory.appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atom = root["electron-persisted-atom-state"] as? [String: Any],
              let unreadByHost = atom["unread-thread-ids-by-host-v1"] as? [String: Any]
        else {
            return []
        }
        var ids = Set<String>()
        for (_, value) in unreadByHost {
            if let list = value as? [String] {
                ids.formUnion(list)
            }
        }
        return ids
    }

    private func readRecentThreadSummaries() -> [(id: String, title: String, modified: Date)] {
        let sessionsRoot = HubCodexCLI.codexHomeDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, date))
        }
        files.sort { $0.date > $1.date }

        var result: [(id: String, title: String, modified: Date)] = []
        var seen = Set<String>()
        for file in files.prefix(40) {
            let name = file.url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "-")
            let uuid = parts.suffix(5).joined(separator: "-")
            let id = uuid.count > 20 ? uuid : name
            guard seen.insert(id).inserted else { continue }
            let title = peekSessionTitle(file.url) ?? String(id.prefix(12))
            result.append((id, title, file.date))
            if result.count >= 12 { break }
        }
        return result
    }

    private func peekSessionTitle(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8_192)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(30) {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }
            if let title = obj["title"] as? String, !title.isEmpty { return title }
            if let payload = obj["payload"] as? [String: Any],
               let title = payload["title"] as? String, !title.isEmpty
            {
                return title
            }
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.isEmpty
            {
                return String(content.prefix(42))
            }
        }
        return nil
    }

    // MARK: - Agent keys

    private func handleAgentTap(index: Int, forceFront: Bool) async throws {
        let now = Date()
        let isDouble: Bool
        if let last = lastAgentTapAt[index], now.timeIntervalSince(last) <= Self.doubleTapWindow {
            isDouble = true
            lastAgentTapAt[index] = nil
        } else {
            isDouble = forceFront
            lastAgentTapAt[index] = now
        }

        state.selectedAgentIndex = index
        if state.agents.indices.contains(index) {
            for i in state.agents.indices {
                state.agents[i].isSelected = (i == index)
            }
        }
        publish()

        let bringFront = forceFront || isDouble
        let threadId = state.agents.indices.contains(index) ? state.agents[index].threadId : nil
        if let threadId, !threadId.isEmpty {
            try await openCodexDeepLink("codex://threads/\(threadId)", activate: bringFront)
        } else {
            // Empty agent slot → create a new Codex chat (not merely activate the app).
            try await openCodexDeepLink("codex://threads/new", activate: bringFront)
        }
    }

    // MARK: - Dial

    private func handleDialTurn(steps: Int) async throws {
        let delta = steps > 0 ? 1 : -1
        state.reasoningLevel = max(0, min(Self.reasoningLevels.count - 1, state.reasoningLevel + delta))
        state.dialCancelArmed = false
        publish()
    }

    private func handleDialPress() async throws {
        // Reasoning dial is display-only without CLI/key injection; open Settings instead.
        try await openCodexDeepLink("codex://settings")
        state.lastControlError = "请在 Codex 设置中调节推理强度。"
        publish()
    }

    // MARK: - Actions (deep link / activate only)

    private func perform(_ action: HubCodexMicroAction, handsFree: Bool = false) async throws {
        // Ignore legacy GUI actions still present on older phone builds.
        guard HubCodexMicroMapping.codexPadSupportedActions.contains(action) else {
            state.lastControlError = "该按键在当前版本不可用，请到设置中重新映射。"
            publish()
            return
        }

        switch action {
        case .none:
            return
        case .focusChatGPT:
            try await activateTarget(bringToFront: true)
            state.lastControlError = nil
            publish()
        case .pushToTalk:
            try await beginPushToTalk(handsFree: handsFree)
        case .continueNewChat, .newChat:
            try await openCodexDeepLink("codex://threads/new")
            state.lastControlError = nil
            publish()
        case .scheduledTasks:
            try await openCodexDeepLink("codex://automations")
            state.lastControlError = nil
            publish()
        case .openSkills:
            try await openCodexDeepLink("codex://skills")
            state.lastControlError = nil
            publish()
        case .openSettings:
            try await openCodexDeepLink("codex://settings")
            state.lastControlError = nil
            publish()
        case .sendMessage, .fastMode, .approve, .decline, .planMode, .reasoningEffort,
             .openCommandMenu, .openBrowser, .openTerminal, .reviewChanges, .gitCommit,
             .createPullRequest, .attachFiles, .historyBack, .historyForward, .toggleSidebar:
            // Unreachable when guarded by codexPadSupportedActions; keep for exhaustiveness.
            return
        }
    }

    private func beginPushToTalk(handsFree: Bool) async throws {
        state.recording = .recording
        state.lastControlError = nil
        handsFreeRecording = handsFree
        publish()
        try? await activateTarget(bringToFront: true)
    }

    private func endPushToTalk() async throws {
        guard state.recording == .recording else { return }
        state.recording = .idle
        handsFreeRecording = false
        publish()
    }

    private func insertTranscribedText(_ text: String) async throws {
        state.recording = .processing
        publish()

        do {
            let sessionId: String? = {
                if let idx = state.selectedAgentIndex,
                   state.agents.indices.contains(idx),
                   let tid = state.agents[idx].threadId,
                   !tid.isEmpty
                {
                    return tid
                }
                return nil
            }()

            // App Sandbox blocks Codex CLI from reading ~/.codex — do not use Process/CLI here.
            // Official deep link fills the composer without Accessibility / Input Monitoring.
            try await openCodexWithPrompt(text, sessionId: sessionId)

            state.recording = .ready
            handsFreeRecording = false
            state.lastControlError = "已在 Codex 填入听写内容，请按回车发送。"
            publish()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if state.recording == .ready {
                state.recording = .idle
                state.lastControlError = nil
                publish()
            }
        } catch {
            state.recording = .idle
            handsFreeRecording = false
            state.lastControlError = error.localizedDescription
            publish()
            throw error
        }
    }

    /// Opens Codex with composer prefilled via `codex://…?prompt=` (no CLI, no key injection).
    private func openCodexWithPrompt(_ text: String, sessionId: String?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prefer documented forms:
        //   codex://threads/new?prompt=
        //   codex://new?prompt=
        var opened = false
        if let sessionId, !sessionId.isEmpty,
           let resume = Self.codexURL(host: "threads", path: "/\(sessionId)", prompt: trimmed)
        {
            opened = (try? await openCodexURLReturningSuccess(resume, activate: true)) == true
        }
        if !opened, let neu = Self.codexURL(host: "threads", path: "/new", prompt: trimmed) {
            opened = (try? await openCodexURLReturningSuccess(neu, activate: true)) == true
        }
        if !opened, let neu = Self.codexURL(host: "new", path: nil, prompt: trimmed) {
            opened = (try? await openCodexURLReturningSuccess(neu, activate: true)) == true
        }
        if opened { return }

        // Last resort: open thread/app and leave text on pasteboard (manual ⌘V).
        try await pasteboardHandoff(
            text: trimmed,
            sessionId: sessionId,
            note: "已打开 Codex 并复制文本到剪贴板，请粘贴后回车发送。"
        )
    }

    private static func codexURL(host: String, path: String?, prompt: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = host
        if let path, !path.isEmpty {
            components.path = path.hasPrefix("/") ? path : "/" + path
        }
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
        return components.url
    }

    private func pasteboardHandoff(text: String, sessionId: String?, note: String) async throws {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        if let sessionId, !sessionId.isEmpty {
            try await openCodexDeepLink("codex://threads/\(sessionId)")
        } else {
            try await openCodexDeepLink("codex://threads/new")
        }
        state.lastControlError = note
        publish()
    }

    // MARK: - Target I/O (no Accessibility)

    private func activateTarget(bringToFront: Bool) async throws {
        let bundleId = HubCodexControlTarget.codex.bundleIdentifier
        let hasApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        if !hasApp {
            throw NSError(
                domain: "TreeletHub",
                code: 3101,
                userInfo: [NSLocalizedDescriptionKey: "未安装 Codex / ChatGPT 桌面应用"]
            )
        }
        if bringToFront {
            try await MacAppActivator.launchOrActivateApplication(bundleIdentifier: bundleId, bookmarkURL: nil)
            try? await Task.sleep(nanoseconds: 180_000_000)
        } else if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) == false {
            try await MacAppActivator.launchOrActivateApplication(bundleIdentifier: bundleId, bookmarkURL: nil)
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func openCodexDeepLink(_ string: String, activate: Bool = true) async throws {
        guard let url = URL(string: string) else {
            throw NSError(domain: "TreeletHub", code: 3102, userInfo: [NSLocalizedDescriptionKey: "无效的 Codex 链接"])
        }
        try await openCodexURL(url, activate: activate)
    }

    @discardableResult
    private func openCodexURLReturningSuccess(_ url: URL, activate: Bool) async throws -> Bool {
        try await openCodexURL(url, activate: activate)
        return true
    }

    private func openCodexURL(_ url: URL, activate: Bool) async throws {
        if activate {
            try await activateTarget(bringToFront: true)
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HubCodexControlTarget.codex.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do {
                try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                return
            } catch {
                // Fall through to generic open.
            }
        }
        // Do not spawn `/usr/bin/open` via Process — App Sandbox can SIGABRT the app.
        guard NSWorkspace.shared.open(url) else {
            throw NSError(
                domain: "TreeletHub",
                code: 3102,
                userInfo: [NSLocalizedDescriptionKey: "无法打开 Codex 深链接"]
            )
        }
    }
}
