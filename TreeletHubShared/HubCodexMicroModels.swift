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
/// Wire values for ChatGPT / Cursor remain for decoding older clients; the pad only opens for Codex.
public enum HubCodexControlTarget: String, Codable, Sendable, Equatable, CaseIterable, Identifiable, Hashable {
    /// ChatGPT desktop chat workflow — usually `com.openai.codex`. (Pad retired; launch only.)
    case chatGPT
    /// Codex / agent workflow — deep links + Codex CLI (no Accessibility key injection).
    case codex
    /// Legacy ChatGPT Classic — `com.openai.chat` (Pad retired; launch only.)
    case chatGPTClassic
    /// Cursor IDE (Pad retired; launch only.)
    case cursor

    public var id: String { rawValue }

    /// Targets that open the virtual control pad.
    public static let padSupportedTargets: [HubCodexControlTarget] = [.codex]

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
        self == .codex
    }

    public var showsAgentKeys: Bool {
        self == .codex
    }

    public var defaultDialMode: HubCodexDialMode {
        .reasoningOnly
    }

    /// Resolve from a hub grid slot. Only Codex opens the control pad.
    public static func resolve(bundleIdentifier: String?, displayName: String?) -> HubCodexControlTarget? {
        let bid = (bundleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Explicit Codex labeling on the shared OpenAI desktop bundle.
        if name.contains("codex") {
            return .codex
        }
        // Bundle alone is ambiguous (ChatGPT vs Codex); require Codex in the name.
        if bid == HubCodexControlTarget.codex.bundleIdentifier || bid == "com.openai.chatgpt" {
            return nil
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
        _ = target
        // Deep-link / activate only — no Accessibility key injection, no sandboxed CLI.
        return [
            .pushToTalk,
            .newChat,
            .openSkills,
            .scheduledTasks,
            .openSettings,
            .focusChatGPT
        ]
    }

    public static func defaultJoystick(for target: HubCodexControlTarget) -> [String: HubCodexMicroAction] {
        _ = target
        return [
            HubCodexJoystickDirection.up.rawValue: .newChat,
            HubCodexJoystickDirection.right.rawValue: .openSkills,
            HubCodexJoystickDirection.down.rawValue: .openSettings,
            HubCodexJoystickDirection.left.rawValue: .scheduledTasks
        ]
    }

    /// Actions that actually do something under the App Store–safe Codex pad.
    public static let codexPadSupportedActions: Set<HubCodexMicroAction> = [
        .none,
        .pushToTalk,
        .newChat,
        .continueNewChat,
        .openSkills,
        .scheduledTasks,
        .openSettings,
        .focusChatGPT
    ]

    /// Remap picker — only supported actions.
    public static func remappableActions(for target: HubCodexControlTarget) -> [HubCodexMicroAction] {
        _ = target
        return [
            .pushToTalk,
            .newChat,
            .continueNewChat,
            .openSkills,
            .scheduledTasks,
            .openSettings,
            .focusChatGPT,
            .none
        ]
    }

    /// Drop GUI-only / broken bindings from older layouts.
    public func sanitizedForCodexPad() -> HubCodexMicroMapping {
        let supported = Self.codexPadSupportedActions
        let fallback = Self.defaultCommandKeys(for: .codex)
        var keys = commandKeys
        while keys.count < 6 { keys.append(.none) }
        keys = Array(keys.prefix(6)).enumerated().map { index, action in
            supported.contains(action) ? action : fallback[index]
        }
        var stick = joystick
        let defaultStick = Self.defaultJoystick(for: .codex)
        for direction in HubCodexJoystickDirection.allCases {
            let key = direction.rawValue
            let action = stick[key] ?? .none
            if !supported.contains(action) {
                stick[key] = defaultStick[key] ?? .focusChatGPT
            }
        }
        var copy = self
        copy.commandKeys = keys
        copy.joystick = stick
        copy.allowsTextAutomation = false
        copy.dialMode = .reasoningOnly
        return copy
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
        controlTarget: HubCodexControlTarget = .codex,
        targetInstalled: Bool = false,
        targetRunning: Bool = false,
        targetDisplayName: String = HubCodexControlTarget.codex.displayNameEN,
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

    /// Ready when Codex app and/or CLI path is available (`accessibilityGranted` is reused as controlReady on the wire).
    public var canControl: Bool {
        targetInstalled || accessibilityGranted || automationReady
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
