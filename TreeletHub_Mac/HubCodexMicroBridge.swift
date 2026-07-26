import AppKit
import ApplicationServices
import Combine
import Foundation

/// Bridges TreeletHub ↔ ChatGPT / Codex / Cursor on Mac.
@MainActor
final class HubCodexMicroBridge: ObservableObject {
    private static let mappingDefaultsKeyPrefix = "treelethub.codexMicro.mapping."
    private static let targetDefaultsKey = "treelethub.codexMicro.controlTarget"
    private static let doubleTapWindow: TimeInterval = 0.35
    private static let reasoningLevels = ["minimal", "low", "medium", "high", "xhigh"]

    @Published private(set) var state: HubCodexMicroState = .empty

    /// Minimum spacing between two automation bursts; blocks runaway key floods.
    private static let minimumCommandInterval: TimeInterval = 0.25
    /// If more than this many commands arrive inside `burstWindow`, automation pauses.
    private static let burstLimit = 12
    private static let burstWindow: TimeInterval = 3.0

    private var pollTask: Task<Void, Never>?
    private var stateObservers: [() -> Void] = []
    private var lastAgentTapAt: [Int: Date] = [:]
    private var handsFreeRecording = false
    private var controlTarget: HubCodexControlTarget = .chatGPT
    private var lastCommandAt: Date?
    private var recentCommandTimestamps: [Date] = []
    private var isPerformingCommand = false

    init() {
        controlTarget = Self.loadTarget()
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
        // State reads and mapping edits never touch the target app, so they bypass throttling.
        if Self.isPassiveCommand(command.kind) {
            try await handleInner(command)
            refreshState()
            return
        }

        // PTT lifecycle and transcribed-text insertion must never be throttled or dropped.
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

        guard !isPerformingCommand else {
            // A previous burst is still running; silently drop instead of queueing.
            return
        }
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
            return .reject("指令过于频繁，已暂停自动化以保护目标应用")
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
            _ = HubMacPrivacyPermissions.requestAccessibilityAccess()
            HubMacPrivacyPermissions.openAccessibilitySettings()
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
            try await sendKeyCode(53) // Escape
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
        let availability = HubCodexControlTarget.allCases.map { target -> HubCodexTargetAvailability in
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) != nil
            let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == target.bundleIdentifier }
            return HubCodexTargetAvailability(target: target, installed: installed, running: running)
        }

        // Auto-pick first installed target if current one is missing.
        if availability.first(where: { $0.target == controlTarget })?.installed != true {
            if let fallback = availability.first(where: \.installed)?.target {
                controlTarget = fallback
                Self.saveTarget(fallback)
            }
        }

        let current = availability.first(where: { $0.target == controlTarget })
        let installed = current?.installed == true
        let running = current?.running == true
        let ax = HubMacPrivacyPermissions.hasAccessibilityAccess

        var agents: [HubCodexAgentSlot]
        switch controlTarget {
        case .chatGPT, .chatGPTClassic, .codex:
            agents = readAgentsFromLocalState()
            if agents.allSatisfy({ $0.status == .unassigned }), running {
                agents = heuristicAgentsWhileRunning(title: controlTarget.displayNameEN)
            }
        case .cursor:
            agents = heuristicAgentsWhileRunning(title: running ? "Cursor" : nil)
            if !running {
                agents = (0..<6).map { HubCodexAgentSlot(id: $0, status: .unassigned) }
            }
        }

        if let selected = state.selectedAgentIndex, agents.indices.contains(selected) {
            for i in agents.indices {
                agents[i].isSelected = (i == selected)
            }
        }

        state.agents = agents
        state.controlTarget = controlTarget
        state.targetInstalled = installed
        state.targetRunning = running
        state.targetDisplayName = controlTarget.displayNameEN
        state.chatGPTRunning = running
        state.chatGPTBundleId = controlTarget.bundleIdentifier
        state.accessibilityGranted = ax
        state.automationReady = ax
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
        var normalized = mapping
        if normalized.commandKeys.count != 6 {
            normalized.commandKeys = HubCodexMicroMapping.defaultCommandKeys(for: controlTarget)
        }
        if normalized.customAgentThreadIds.count != 6 {
            normalized.customAgentThreadIds = Array(repeating: nil, count: 6)
        }
        state.mapping = normalized
        Self.saveMapping(normalized, for: controlTarget)
        publish()
    }

    private func setControlTarget(_ target: HubCodexControlTarget) {
        controlTarget = target
        Self.saveTarget(target)
        state.controlTarget = target
        state.mapping = Self.loadMapping(for: target)
        state.lastControlError = nil
        refreshState()
    }

    private static func loadMapping(for target: HubCodexControlTarget) -> HubCodexMicroMapping {
        let key = mappingDefaultsKeyPrefix + target.rawValue
        if let data = UserDefaults.standard.data(forKey: key),
           let mapping = try? JSONDecoder().decode(HubCodexMicroMapping.self, from: data)
        {
            return mapping
        }
        // Migrate legacy single-mapping store once.
        if let data = UserDefaults.standard.data(forKey: "treelethub.codexMicro.mapping"),
           let mapping = try? JSONDecoder().decode(HubCodexMicroMapping.self, from: data),
           target == .codex
        {
            saveMapping(mapping, for: target)
            return mapping
        }
        return .default(for: target)
    }

    private static func saveMapping(_ mapping: HubCodexMicroMapping, for target: HubCodexControlTarget) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        UserDefaults.standard.set(data, forKey: mappingDefaultsKeyPrefix + target.rawValue)
    }

    private static func loadMapping() -> HubCodexMicroMapping {
        loadMapping(for: .codex)
    }

    private static func saveMapping(_ mapping: HubCodexMicroMapping) {
        saveMapping(mapping, for: .codex)
    }

    private static func loadTarget() -> HubCodexControlTarget {
        if let raw = UserDefaults.standard.string(forKey: targetDefaultsKey),
           let target = HubCodexControlTarget(rawValue: raw)
        {
            return target
        }
        // Prefer installed unified ChatGPT, then Cursor, then Classic.
        for target in [HubCodexControlTarget.codex, .chatGPT, .cursor, .chatGPTClassic] {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) != nil {
                return target
            }
        }
        return .codex
    }

    private static func saveTarget(_ target: HubCodexControlTarget) {
        UserDefaults.standard.set(target.rawValue, forKey: targetDefaultsKey)
    }

    // MARK: - Local Codex status

    private func readAgentsFromLocalState() -> [HubCodexAgentSlot] {
        let unread = readUnreadThreadIds()
        let recent = readRecentThreadSummaries()
        let source = state.mapping.agentSource
        let dates = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0.modified) })

        var chosen: [(id: String, title: String)] = []
        switch source {
        case .mostRecent:
            chosen = recent.prefix(6).map { ($0.id, $0.title) }
        case .pinned:
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
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/.codex-global-state.json")
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
        let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
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
        switch controlTarget {
        case .chatGPT, .codex:
            let threadId = state.agents.indices.contains(index) ? state.agents[index].threadId : nil
            if let threadId, !threadId.isEmpty {
                try await openCodexDeepLink("codex://threads/\(threadId)", activate: bringFront)
            } else if state.mapping.agentSource == .custom {
                try await openCodexDeepLink("codex://threads/new", activate: bringFront)
            } else {
                try await activateTarget(bringToFront: bringFront)
            }
        case .chatGPTClassic:
            try await activateTarget(bringToFront: true)
            // Cycle chats as best-effort.
            for _ in 0..<max(0, index) {
                try await sendKeyCode(30, using: [.command, .shift]) // ]
            }
        case .cursor:
            try await activateTarget(bringToFront: true)
            if index == 0 {
                try await sendKeyCode(37, using: [.command]) // Cmd+L chat
            } else {
                try await sendKeyCode(34, using: [.command]) // Cmd+I composer/agent
            }
        }
    }

    // MARK: - Dial

    /// Turning only moves the local selection. Nothing is sent to the target app until
    /// the dial is pressed, so scrubbing can never spam the composer.
    private func handleDialTurn(steps: Int) async throws {
        guard state.mapping.dialMode == .reasoningOnly else {
            // Composer navigation still needs arrow keys, but one per committed step.
            try await activateTarget(bringToFront: true)
            try await sendKeyCode(steps > 0 ? 125 : 126)
            return
        }
        let delta = steps > 0 ? 1 : -1
        state.reasoningLevel = max(0, min(Self.reasoningLevels.count - 1, state.reasoningLevel + delta))
        state.dialCancelArmed = false
        publish()
    }

    private func handleDialPress() async throws {
        try await activateTarget(bringToFront: true)
        switch controlTarget {
        case .chatGPT, .chatGPTClassic, .codex:
            if state.mapping.dialMode == .reasoningOnly {
                let level = Self.reasoningLevels[max(0, min(Self.reasoningLevels.count - 1, state.reasoningLevel))]
                try await runCommandPalette("reasoning \(level)")
            } else {
                try await sendKeyCode(36)
            }
        case .cursor:
            try await sendKeyCode(34, using: [.command]) // Cmd+I
        }
    }

    // MARK: - Actions

    private func perform(_ action: HubCodexMicroAction, handsFree: Bool = false) async throws {
        switch action {
        case .none:
            return
        case .focusChatGPT:
            try await activateTarget(bringToFront: true)
            return
        case .pushToTalk:
            // Begin owns activation so the mic can start before the target app comes forward.
            try await beginPushToTalk(handsFree: handsFree)
            return
        default:
            break
        }

        try await activateTarget(bringToFront: true)

        switch controlTarget {
        case .chatGPT, .codex:
            try await performChatGPTAction(action, handsFree: handsFree, allowDeepLinks: true)
        case .chatGPTClassic:
            try await performChatGPTAction(action, handsFree: handsFree, allowDeepLinks: false)
        case .cursor:
            try await performCursorAction(action, handsFree: handsFree)
        }
    }

    private func performChatGPTAction(_ action: HubCodexMicroAction, handsFree: Bool, allowDeepLinks: Bool) async throws {
        switch action {
        case .fastMode:
            try await runCommandPalette("fast mode")
        case .approve:
            try await runCommandPalette("approve")
        case .decline:
            try await runCommandPalette("decline")
        case .continueNewChat, .newChat:
            if allowDeepLinks {
                try await openCodexDeepLink("codex://threads/new")
            } else {
                try await sendKeyCode(45, using: [.command]) // Cmd+N
            }
        case .pushToTalk:
            try await beginPushToTalk(handsFree: handsFree)
        case .sendMessage:
            try await sendComposerMessage()
        case .openBrowser:
            try await runCommandPalette("browser")
        case .openTerminal:
            try await sendKeyCode(50, using: [.control]) // Ctrl+`
        case .reviewChanges:
            try await sendKeyCode(5, using: [.control, .shift]) // Ctrl+Shift+G
        case .gitCommit:
            try await runCommandPalette("commit")
        case .createPullRequest:
            try await runCommandPalette("pull request")
        case .attachFiles:
            try await sendKeyCode(31, using: [.command]) // Cmd+O
        case .scheduledTasks:
            if allowDeepLinks {
                try await openCodexDeepLink("codex://automations")
            } else {
                try await runCommandPalette("scheduled")
            }
        case .reasoningEffort:
            try await handleDialPress()
        case .openSkills:
            if allowDeepLinks {
                try await openCodexDeepLink("codex://skills")
            } else {
                try await runCommandPalette("skills")
            }
        case .planMode:
            try await runCommandPalette("plan mode")
        case .historyBack:
            try await sendKeyCode(33, using: [.command]) // Cmd+[
        case .historyForward:
            try await sendKeyCode(30, using: [.command]) // Cmd+]
        case .toggleSidebar:
            try await sendKeyCode(11, using: [.command]) // Cmd+B
        case .openSettings:
            if allowDeepLinks {
                try await openCodexDeepLink("codex://settings")
            } else {
                try await sendKeyCode(43, using: [.command]) // Cmd+,
            }
        case .openCommandMenu:
            try await sendKeyCode(40, using: [.command]) // Cmd+K
        case .focusChatGPT, .none:
            break
        }
    }

    private func performCursorAction(_ action: HubCodexMicroAction, handsFree: Bool) async throws {
        switch action {
        case .fastMode, .planMode, .reasoningEffort:
            try await sendKeyCode(35, using: [.command, .shift]) // Cmd+Shift+P
        case .approve:
            try await sendKeyCode(36, using: [.command]) // Cmd+Return accept
        case .decline:
            try await sendKeyCode(53) // Escape
        case .continueNewChat, .newChat:
            try await sendKeyCode(37, using: [.command]) // Cmd+L
            try? await Task.sleep(nanoseconds: 120_000_000)
            try await sendKeyCode(45, using: [.command]) // Cmd+N in chat when possible
        case .pushToTalk:
            try await beginPushToTalk(handsFree: handsFree)
        case .sendMessage:
            try await sendComposerMessage()
        case .openBrowser:
            try await sendKeyCode(35, using: [.command, .shift])
            try? await Task.sleep(nanoseconds: 150_000_000)
            try await typeTextViaSystemEvents("Simple Browser")
            try await sendKeyCode(36)
        case .openTerminal:
            try await sendKeyCode(50, using: [.control]) // Ctrl+`
        case .reviewChanges:
            try await sendKeyCode(5, using: [.control, .shift]) // source control-ish
        case .gitCommit:
            try await sendKeyCode(5, using: [.control, .shift])
        case .createPullRequest:
            try await sendKeyCode(35, using: [.command, .shift])
            try? await Task.sleep(nanoseconds: 150_000_000)
            try await typeTextViaSystemEvents("Create Pull Request")
            try await sendKeyCode(36)
        case .attachFiles:
            try await sendKeyCode(31, using: [.command])
        case .scheduledTasks, .openSkills:
            try await sendKeyCode(35, using: [.command, .shift])
        case .historyBack:
            try await sendKeyCode(33, using: [.command])
        case .historyForward:
            try await sendKeyCode(30, using: [.command])
        case .toggleSidebar:
            try await sendKeyCode(11, using: [.command])
        case .openSettings:
            try await sendKeyCode(43, using: [.command])
        case .openCommandMenu:
            try await sendKeyCode(35, using: [.command, .shift])
        case .focusChatGPT:
            try await sendKeyCode(37, using: [.command]) // Cmd+L
        case .none:
            break
        }
    }

    private func beginPushToTalk(handsFree: Bool) async throws {
        // Cancel any leftover session, then start local mic STT immediately so short holds still capture audio.
        // Recording happens on the iPhone; the Mac just mirrors the state and pre-focuses the composer.
        state.recording = .recording
        state.lastControlError = nil
        handsFreeRecording = handsFree
        publish()

        try? await activateTarget(bringToFront: true)
        try? await focusComposerForDictation()
    }

    private func endPushToTalk() async throws {
        // iOS sends the transcribed text separately via kindInsertText; end just clears the badge.
        guard state.recording == .recording else { return }
        state.recording = .idle
        handsFreeRecording = false
        publish()
    }

    /// iOS finished on-device speech recognition — paste the text into the target composer.
    private func insertTranscribedText(_ text: String) async throws {
        state.recording = .processing
        publish()

        do {
            try await activateTarget(bringToFront: true)
            try await focusComposerForDictation()
            try? await Task.sleep(nanoseconds: 120_000_000)
            try await pasteTextIntoComposer(text)
            state.recording = .ready
            state.lastControlError = nil
            handsFreeRecording = false
            publish()
        } catch {
            state.recording = .idle
            handsFreeRecording = false
            state.lastControlError = error.localizedDescription
            publish()
            throw error
        }
    }

    /// Best-effort: put keyboard focus into the chat/composer so pasted text lands correctly.
    private func focusComposerForDictation() async throws {
        switch controlTarget {
        case .chatGPT, .chatGPTClassic, .codex:
            // Do not send Escape — it often blurs the composer. Activation is usually enough.
            try? await Task.sleep(nanoseconds: 80_000_000)
        case .cursor:
            try await sendKeyCode(37, using: [.command]) // Cmd+L chat
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func pasteTextIntoComposer(_ text: String) async throws {
        let board = NSPasteboard.general
        let previous = board.string(forType: .string)
        board.clearContents()
        board.setString(text, forType: .string)
        try await sendKeyCode(9, using: [.command]) // Cmd+V
        try? await Task.sleep(nanoseconds: 80_000_000)
        if let previous {
            board.clearContents()
            board.setString(previous, forType: .string)
        }
    }

    private func sendComposerMessage() async throws {
        try await sendKeyCode(36, using: [.command])
        try? await Task.sleep(nanoseconds: 40_000_000)
        try await sendKeyCode(36)
        if state.recording == .ready || state.recording == .processing {
            state.recording = .idle
            publish()
        }
    }

    // MARK: - Target I/O

    private func activateTarget(bringToFront: Bool) async throws {
        let bundleId = controlTarget.bundleIdentifier
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            throw NSError(
                domain: "TreeletHub",
                code: 3101,
                userInfo: [NSLocalizedDescriptionKey: "未安装 \(controlTarget.displayNameEN)"]
            )
        }
        if bringToFront {
            try await MacAppActivator.launchOrActivateApplication(bundleIdentifier: bundleId, bookmarkURL: nil)
            try? await Task.sleep(nanoseconds: 220_000_000)
            try? await bringProcessFrontmost(bundleId: bundleId)
        } else if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) == false {
            try await MacAppActivator.launchOrActivateApplication(bundleIdentifier: bundleId, bookmarkURL: nil)
            try? await Task.sleep(nanoseconds: 220_000_000)
        }
    }

    private func openCodexDeepLink(_ string: String, activate: Bool = true) async throws {
        guard controlTarget.supportsCodexDeepLinks else {
            try await activateTarget(bringToFront: true)
            return
        }
        if activate {
            try await activateTarget(bringToFront: true)
        }
        // Prefer opening against the selected app explicitly.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: controlTarget.bundleIdentifier),
           let url = URL(string: string)
        {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do {
                try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                return
            } catch {
                // Fall through to generic open.
            }
        }
        guard let url = URL(string: string) else {
            throw NSError(domain: "TreeletHub", code: 3102, userInfo: [NSLocalizedDescriptionKey: "无效的 Codex 链接"])
        }
        if !NSWorkspace.shared.open(url) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", controlTarget.bundleIdentifier, string]
            try process.run()
            process.waitUntilExit()
        }
    }

    /// Opens the target's command palette. Typing the query is opt-in because a palette
    /// that fails to open turns every keystroke into chat input.
    private func runCommandPalette(_ query: String) async throws {
        // Official docs: Command menu = Cmd+Shift+P (Cmd+K often maps to search chats).
        try await sendKeyCode(35, using: [.command, .shift])

        guard state.mapping.allowsTextAutomation else {
            throw NSError(
                domain: "TreeletHub",
                code: 3106,
                userInfo: [NSLocalizedDescriptionKey: "hint:palette:\(query)"]
            )
        }

        try? await Task.sleep(nanoseconds: 320_000_000)
        guard isTargetFrontmost() else {
            throw NSError(
                domain: "TreeletHub",
                code: 3107,
                userInfo: [NSLocalizedDescriptionKey: "\(controlTarget.displayNameEN) 不在前台，已取消输入以避免误触"]
            )
        }
        try await typeTextViaSystemEvents(query)
        try? await Task.sleep(nanoseconds: 160_000_000)
        try await sendKeyCode(36)
    }

    private func isTargetFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == controlTarget.bundleIdentifier
    }

    private enum KeyModifier {
        case command, shift, option, control
    }

    private func sendKeyCode(_ keyCode: Int, using modifiers: [KeyModifier] = []) async throws {
        ensureControlPermissions()
        // Prefer System Events — works more reliably from sandboxed apps with Automation.
        do {
            try await sendKeyViaSystemEvents(keyCode: keyCode, modifiers: modifiers)
            return
        } catch {
            // Fallback to CGEvent.
            try await sendKeyViaCGEvent(keyCode: CGKeyCode(keyCode), modifiers: modifiers)
        }
    }

    private func ensureControlPermissions() {
        if !HubMacPrivacyPermissions.hasAccessibilityAccess {
            _ = HubMacPrivacyPermissions.requestAccessibilityAccess()
        }
    }

    private func bringProcessFrontmost(bundleId: String) async throws {
        let script = """
        tell application "System Events"
          set procs to every process whose bundle identifier is "\(bundleId)"
          if (count of procs) > 0 then
            set frontmost of item 1 of procs to true
          end if
        end tell
        """
        _ = try? runAppleScript(script)
    }

    private func sendKeyViaSystemEvents(keyCode: Int, modifiers: [KeyModifier]) async throws {
        var usingParts: [String] = []
        if modifiers.contains(.command) { usingParts.append("command down") }
        if modifiers.contains(.shift) { usingParts.append("shift down") }
        if modifiers.contains(.option) { usingParts.append("option down") }
        if modifiers.contains(.control) { usingParts.append("control down") }
        let usingClause = usingParts.isEmpty ? "" : " using {\(usingParts.joined(separator: ", "))}"
        let script = """
        tell application "System Events"
          key code \(keyCode)\(usingClause)
        end tell
        """
        try runAppleScript(script)
        try? await Task.sleep(nanoseconds: 45_000_000)
    }

    private func typeTextViaSystemEvents(_ text: String) async throws {
        ensureControlPermissions()
        guard state.mapping.allowsTextAutomation else {
            throw NSError(
                domain: "TreeletHub",
                code: 3106,
                userInfo: [NSLocalizedDescriptionKey: "已阻止自动输入文字（可在设置中开启「命令面板自动输入」）"]
            )
        }
        guard isTargetFrontmost() else {
            throw NSError(
                domain: "TreeletHub",
                code: 3107,
                userInfo: [NSLocalizedDescriptionKey: "\(controlTarget.displayNameEN) 不在前台，已取消输入以避免误触"]
            )
        }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
          keystroke "\(escaped)"
        end tell
        """
        try runAppleScript(script)
        try? await Task.sleep(nanoseconds: 40_000_000)
    }

    private func sendKeyViaCGEvent(keyCode: CGKeyCode, modifiers: [KeyModifier]) async throws {
        guard HubMacPrivacyPermissions.hasAccessibilityAccess else {
            throw NSError(
                domain: "TreeletHub",
                code: 3103,
                userInfo: [NSLocalizedDescriptionKey: "需要在 Mac「系统设置 → 隐私与安全性 → 辅助功能」中允许 TreeletHub"]
            )
        }
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 40_000_000)
    }

    @discardableResult
    private func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String)
                ?? String(describing: error)
            // Common first-run: user must approve Automation for System Events.
            if message.localizedCaseInsensitiveContains("not allowed")
                || message.localizedCaseInsensitiveContains("没有权限")
                || message.localizedCaseInsensitiveContains("(-1743)")
            {
                throw NSError(
                    domain: "TreeletHub",
                    code: 3104,
                    userInfo: [NSLocalizedDescriptionKey: "请在 Mac「系统设置 → 隐私与安全性 → 自动化」中允许 TreeletHub 控制「系统事件」和目标 App"]
                )
            }
            throw NSError(
                domain: "TreeletHub",
                code: 3105,
                userInfo: [NSLocalizedDescriptionKey: "控制失败：\(message)"]
            )
        }
        return result
    }
}
