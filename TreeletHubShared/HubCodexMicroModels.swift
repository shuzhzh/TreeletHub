import Foundation

// MARK: - Agent status (matches Codex Micro RGB legend)

public enum HubCodexAgentStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case thinking
    case complete
    case requiresInput
    case error
    case unassigned

    /// Official Codex Micro light language.
    public var displayNameEN: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .complete: return "Complete"
        case .requiresInput: return "Requires input"
        case .error: return "Error"
        case .unassigned: return "No assigned chat"
        }
    }
}

public enum HubCodexAgentSource: String, Codable, Sendable, Equatable, CaseIterable {
    case mostRecent
    case pinned
    case priority
    case custom
}

public enum HubCodexDialMode: String, Codable, Sendable, Equatable, CaseIterable {
    /// Turn dial to move composer controls; press to open/select.
    case composerNavigation
    /// Turn dial only adjusts reasoning effort.
    case reasoningOnly
}

public enum HubCodexJoystickDirection: String, Codable, Sendable, Equatable, CaseIterable {
    case up
    case right
    case down
    case left
}

public enum HubCodexRecordingState: String, Codable, Sendable, Equatable {
    case idle
    case recording
    case processing
    case ready
}

/// Which Mac app / workflow the virtual pad currently drives.
public enum HubCodexControlTarget: String, Codable, Sendable, Equatable, CaseIterable, Identifiable, Hashable {
    /// ChatGPT desktop chat workflow — usually `com.openai.codex`.
    case chatGPT
    /// Codex / agent workflow on the unified ChatGPT app — same bundle, different pad layout.
    case codex
    /// Legacy ChatGPT Classic — `com.openai.chat`
    case chatGPTClassic
    /// Cursor IDE — `com.todesktop.230313mzl4w4u92`
    case cursor

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .chatGPT, .codex: return "com.openai.codex"
        case .chatGPTClassic: return "com.openai.chat"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        }
    }

    public var displayNameEN: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .codex: return "Codex"
        case .chatGPTClassic: return "ChatGPT Classic"
        case .cursor: return "Cursor"
        }
    }

    public var supportsCodexDeepLinks: Bool {
        self == .chatGPT || self == .codex
    }

    public var showsAgentKeys: Bool {
        switch self {
        case .codex, .chatGPT, .chatGPTClassic: return true
        case .cursor: return false
        }
    }

    public var defaultDialMode: HubCodexDialMode {
        switch self {
        case .codex: return .reasoningOnly
        case .chatGPT, .chatGPTClassic, .cursor: return .composerNavigation
        }
    }

    /// Resolve from a hub grid slot (bundle id + display name).
    public static func resolve(bundleIdentifier: String?, displayName: String?) -> HubCodexControlTarget? {
        let bid = (bundleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if bid == HubCodexControlTarget.cursor.bundleIdentifier
            || name == "cursor"
            || name.contains("cursor")
        {
            return .cursor
        }
        if bid == HubCodexControlTarget.chatGPTClassic.bundleIdentifier
            || name.contains("classic")
        {
            return .chatGPTClassic
        }
        if bid == HubCodexControlTarget.chatGPT.bundleIdentifier
            || bid == "com.openai.chatgpt"
            || name.contains("chatgpt")
            || name.contains("chat gpt")
            || name == "gpt"
        {
            // Same bundle can be labeled Codex on the grid.
            if name.contains("codex") { return .codex }
            return .chatGPT
        }
        if name.contains("codex") {
            return .codex
        }
        return nil
    }
}

public struct HubCodexTargetAvailability: Codable, Sendable, Equatable, Identifiable {
    public var id: String { target.rawValue }
    public var target: HubCodexControlTarget
    public var installed: Bool
    public var running: Bool

    public init(target: HubCodexControlTarget, installed: Bool, running: Bool) {
        self.target = target
        self.installed = installed
        self.running = running
    }
}

/// Actions that can be bound to Command Keys / joystick / dial press.
public enum HubCodexMicroAction: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case fastMode
    case approve
    case decline
    case continueNewChat
    case pushToTalk
    case sendMessage
    case newChat
    case openBrowser
    case openTerminal
    case reviewChanges
    case gitCommit
    case createPullRequest
    case attachFiles
    case scheduledTasks
    case reasoningEffort
    case openSkills
    case planMode
    case historyBack
    case historyForward
    case toggleSidebar
    case openSettings
    case openCommandMenu
    case focusChatGPT
    case none

    public var id: String { rawValue }

    public var defaultSymbolName: String {
        switch self {
        case .fastMode: return "hare.fill"
        case .approve: return "checkmark.circle.fill"
        case .decline: return "xmark.circle.fill"
        case .continueNewChat: return "arrow.triangle.branch"
        case .pushToTalk: return "mic.fill"
        case .sendMessage: return "paperplane.fill"
        case .newChat: return "plus.bubble.fill"
        case .openBrowser: return "globe"
        case .openTerminal: return "terminal.fill"
        case .reviewChanges: return "doc.text.magnifyingglass"
        case .gitCommit: return "arrow.up.to.line.compact"
        case .createPullRequest: return "arrow.triangle.pull"
        case .attachFiles: return "paperclip"
        case .scheduledTasks: return "calendar"
        case .reasoningEffort: return "brain.head.profile"
        case .openSkills: return "sparkles"
        case .planMode: return "list.bullet.clipboard"
        case .historyBack: return "chevron.backward"
        case .historyForward: return "chevron.forward"
        case .toggleSidebar: return "sidebar.left"
        case .openSettings: return "gearshape.fill"
        case .openCommandMenu: return "command"
        case .focusChatGPT: return "macwindow"
        case .none: return "circle.dashed"
        }
    }
}

public struct HubCodexAgentSlot: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var status: HubCodexAgentStatus
    public var title: String?
    public var threadId: String?
    public var isSelected: Bool

    public init(
        id: Int,
        status: HubCodexAgentStatus = .unassigned,
        title: String? = nil,
        threadId: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.status = status
        self.title = title
        self.threadId = threadId
        self.isSelected = isSelected
    }
}

public struct HubCodexMicroMapping: Codable, Sendable, Equatable {
    public var commandKeys: [HubCodexMicroAction]
    public var joystick: [String: HubCodexMicroAction]
    public var agentSource: HubCodexAgentSource
    public var dialMode: HubCodexDialMode
    public var customAgentThreadIds: [String?]
    public var brightness: Double
    public var idleLightSeconds: Int
    /// Off by default: actions without a real shortcut must never type free text,
    /// otherwise a missed command palette dumps the query into the chat composer.
    public var allowsTextAutomation: Bool

    public init(
        commandKeys: [HubCodexMicroAction] = HubCodexMicroMapping.defaultCommandKeys,
        joystick: [String: HubCodexMicroAction] = HubCodexMicroMapping.defaultJoystick,
        agentSource: HubCodexAgentSource = .mostRecent,
        dialMode: HubCodexDialMode = .reasoningOnly,
        customAgentThreadIds: [String?] = Array(repeating: nil, count: 6),
        brightness: Double = 1.0,
        idleLightSeconds: Int = 180,
        allowsTextAutomation: Bool = false
    ) {
        self.commandKeys = commandKeys
        self.joystick = joystick
        self.agentSource = agentSource
        self.dialMode = dialMode
        self.customAgentThreadIds = customAgentThreadIds
        self.brightness = brightness
        self.idleLightSeconds = idleLightSeconds
        self.allowsTextAutomation = allowsTextAutomation
    }

    private enum CodingKeys: String, CodingKey {
        case commandKeys, joystick, agentSource, dialMode
        case customAgentThreadIds, brightness, idleLightSeconds, allowsTextAutomation
    }

    /// Tolerant decoding so payloads written by older builds still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandKeys = try c.decodeIfPresent([HubCodexMicroAction].self, forKey: .commandKeys)
            ?? Self.defaultCommandKeys
        joystick = try c.decodeIfPresent([String: HubCodexMicroAction].self, forKey: .joystick)
            ?? Self.defaultJoystick
        agentSource = try c.decodeIfPresent(HubCodexAgentSource.self, forKey: .agentSource) ?? .mostRecent
        dialMode = try c.decodeIfPresent(HubCodexDialMode.self, forKey: .dialMode) ?? .reasoningOnly
        customAgentThreadIds = try c.decodeIfPresent([String?].self, forKey: .customAgentThreadIds)
            ?? Array(repeating: nil, count: 6)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1.0
        idleLightSeconds = try c.decodeIfPresent(Int.self, forKey: .idleLightSeconds) ?? 180
        allowsTextAutomation = try c.decodeIfPresent(Bool.self, forKey: .allowsTextAutomation) ?? false
    }

    public static let defaultCommandKeys: [HubCodexMicroAction] = defaultCommandKeys(for: .codex)

    public static let defaultJoystick: [String: HubCodexMicroAction] = defaultJoystick(for: .codex)

    public static let `default` = HubCodexMicroMapping.default(for: .codex)

    public static func `default`(for target: HubCodexControlTarget) -> HubCodexMicroMapping {
        HubCodexMicroMapping(
            commandKeys: defaultCommandKeys(for: target),
            joystick: defaultJoystick(for: target),
            agentSource: .mostRecent,
            dialMode: target.defaultDialMode,
            allowsTextAutomation: false
        )
    }

    public static func defaultCommandKeys(for target: HubCodexControlTarget) -> [HubCodexMicroAction] {
        switch target {
        case .codex:
            return [.fastMode, .approve, .decline, .continueNewChat, .pushToTalk, .sendMessage]
        case .chatGPT, .chatGPTClassic:
            return [.newChat, .pushToTalk, .sendMessage, .openCommandMenu, .toggleSidebar, .openSettings]
        case .cursor:
            // PTT + Send first so voice → send works out of the box.
            return [.pushToTalk, .sendMessage, .focusChatGPT, .openCommandMenu, .approve, .decline]
        }
    }

    public static func defaultJoystick(for target: HubCodexControlTarget) -> [String: HubCodexMicroAction] {
        switch target {
        case .codex:
            return [
                HubCodexJoystickDirection.up.rawValue: .planMode,
                HubCodexJoystickDirection.right.rawValue: .historyForward,
                HubCodexJoystickDirection.down.rawValue: .toggleSidebar,
                HubCodexJoystickDirection.left.rawValue: .historyBack
            ]
        case .chatGPT, .chatGPTClassic:
            return [
                HubCodexJoystickDirection.up.rawValue: .newChat,
                HubCodexJoystickDirection.right.rawValue: .historyForward,
                HubCodexJoystickDirection.down.rawValue: .toggleSidebar,
                HubCodexJoystickDirection.left.rawValue: .historyBack
            ]
        case .cursor:
            return [
                HubCodexJoystickDirection.up.rawValue: .focusChatGPT,
                HubCodexJoystickDirection.right.rawValue: .reviewChanges,
                HubCodexJoystickDirection.down.rawValue: .openTerminal,
                HubCodexJoystickDirection.left.rawValue: .toggleSidebar
            ]
        }
    }

    /// Actions that make sense to remap for a given target.
    public static func remappableActions(for target: HubCodexControlTarget) -> [HubCodexMicroAction] {
        switch target {
        case .codex:
            return [
                .fastMode, .approve, .decline, .continueNewChat, .pushToTalk, .sendMessage,
                .newChat, .planMode, .reasoningEffort, .openSkills, .reviewChanges,
                .gitCommit, .createPullRequest, .attachFiles, .scheduledTasks,
                .openBrowser, .openTerminal, .historyBack, .historyForward,
                .toggleSidebar, .openSettings, .openCommandMenu, .focusChatGPT
            ]
        case .chatGPT, .chatGPTClassic:
            return [
                .newChat, .pushToTalk, .sendMessage, .openCommandMenu, .toggleSidebar,
                .openSettings, .historyBack, .historyForward, .attachFiles,
                .focusChatGPT, .continueNewChat
            ]
        case .cursor:
            return [
                .focusChatGPT, .openCommandMenu, .approve, .decline, .openTerminal,
                .sendMessage, .reviewChanges, .gitCommit, .createPullRequest,
                .attachFiles, .toggleSidebar, .openSettings, .newChat, .pushToTalk
            ]
        }
    }
}

/// Live snapshot pushed Mac → iOS.
public struct HubCodexMicroState: Codable, Sendable, Equatable {
    public var agents: [HubCodexAgentSlot]
    public var selectedAgentIndex: Int?
    public var recording: HubCodexRecordingState
    public var reasoningLevel: Int
    public var layer: Int
    public var dialCancelArmed: Bool
    public var chatGPTRunning: Bool
    public var chatGPTBundleId: String?
    public var mapping: HubCodexMicroMapping
    public var updatedAt: TimeInterval
    /// Currently selected control target on Mac.
    public var controlTarget: HubCodexControlTarget
    public var targetInstalled: Bool
    public var targetRunning: Bool
    public var targetDisplayName: String
    public var accessibilityGranted: Bool
    public var automationReady: Bool
    public var lastControlError: String?
    public var availableTargets: [HubCodexTargetAvailability]

    public init(
        agents: [HubCodexAgentSlot] = (0..<6).map { HubCodexAgentSlot(id: $0) },
        selectedAgentIndex: Int? = nil,
        recording: HubCodexRecordingState = .idle,
        reasoningLevel: Int = 2,
        layer: Int = 1,
        dialCancelArmed: Bool = false,
        chatGPTRunning: Bool = false,
        chatGPTBundleId: String? = nil,
        mapping: HubCodexMicroMapping = .default,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        controlTarget: HubCodexControlTarget = .chatGPT,
        targetInstalled: Bool = false,
        targetRunning: Bool = false,
        targetDisplayName: String = HubCodexControlTarget.chatGPT.displayNameEN,
        accessibilityGranted: Bool = false,
        automationReady: Bool = false,
        lastControlError: String? = nil,
        availableTargets: [HubCodexTargetAvailability] = []
    ) {
        self.agents = agents
        self.selectedAgentIndex = selectedAgentIndex
        self.recording = recording
        self.reasoningLevel = reasoningLevel
        self.layer = layer
        self.dialCancelArmed = dialCancelArmed
        self.chatGPTRunning = chatGPTRunning
        self.chatGPTBundleId = chatGPTBundleId
        self.mapping = mapping
        self.updatedAt = updatedAt
        self.controlTarget = controlTarget
        self.targetInstalled = targetInstalled
        self.targetRunning = targetRunning
        self.targetDisplayName = targetDisplayName
        self.accessibilityGranted = accessibilityGranted
        self.automationReady = automationReady
        self.lastControlError = lastControlError
        self.availableTargets = availableTargets
    }

    public static let empty = HubCodexMicroState()

    public var canControl: Bool {
        targetInstalled && accessibilityGranted
    }
}

/// iOS → Mac command payload (JSON in `HubWireEnvelope.message`).
public struct HubCodexMicroCommand: Codable, Sendable, Equatable {
    public var kind: String
    public var agentIndex: Int?
    public var action: HubCodexMicroAction?
    public var direction: HubCodexJoystickDirection?
    public var steps: Int?
    public var bringToFront: Bool?
    public var mapping: HubCodexMicroMapping?
    public var handsFree: Bool?
    public var target: HubCodexControlTarget?
    /// Transcribed speech (or any text) to insert into the target app's composer.
    public var text: String?

    public init(
        kind: String,
        agentIndex: Int? = nil,
        action: HubCodexMicroAction? = nil,
        direction: HubCodexJoystickDirection? = nil,
        steps: Int? = nil,
        bringToFront: Bool? = nil,
        mapping: HubCodexMicroMapping? = nil,
        handsFree: Bool? = nil,
        target: HubCodexControlTarget? = nil,
        text: String? = nil
    ) {
        self.kind = kind
        self.agentIndex = agentIndex
        self.action = action
        self.direction = direction
        self.steps = steps
        self.bringToFront = bringToFront
        self.mapping = mapping
        self.handsFree = handsFree
        self.target = target
        self.text = text
    }

    public static let kindAgentTap = "agentTap"
    public static let kindAgentDoubleTap = "agentDoubleTap"
    public static let kindCommand = "command"
    public static let kindJoystick = "joystick"
    public static let kindDialTurn = "dialTurn"
    public static let kindDialPress = "dialPress"
    public static let kindDialLongPress = "dialLongPress"
    public static let kindDialCancel = "dialCancel"
    public static let kindLayerCycle = "layerCycle"
    public static let kindRequestState = "requestState"
    public static let kindSetMapping = "setMapping"
    public static let kindSetTarget = "setTarget"
    public static let kindOpenAccessibilitySettings = "openAccessibilitySettings"
    public static let kindPushToTalkEnd = "pushToTalkEnd"
    /// iOS did on-device speech recognition; Mac only pastes the text into the composer.
    public static let kindInsertText = "insertText"
}

public enum HubCodexMicroWire {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder = JSONDecoder()

    public static func encodeCommand(_ command: HubCodexMicroCommand) -> String? {
        guard let data = try? encoder.encode(command) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeCommand(_ message: String?) -> HubCodexMicroCommand? {
        guard let message, let data = message.data(using: .utf8) else { return nil }
        return try? decoder.decode(HubCodexMicroCommand.self, from: data)
    }

    public static func encodeState(_ state: HubCodexMicroState) -> String? {
        guard let data = try? encoder.encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeState(_ message: String?) -> HubCodexMicroState? {
        guard let message, let data = message.data(using: .utf8) else { return nil }
        return try? decoder.decode(HubCodexMicroState.self, from: data)
    }
}
