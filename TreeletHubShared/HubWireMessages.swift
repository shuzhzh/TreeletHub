import Foundation

/// 局域网 JSON 行协议（每行一条 JSON，UTF-8，以 `\n` 结尾）
public struct HubWireEnvelope: Codable, Sendable, Equatable {
    public var op: String
    public var pin: String?
    public var deviceName: String?
    public var deviceId: String?
    public var ok: Bool?
    public var slots: [HubSlotConfig]?
    public var pages: [HubPageConfig]?
    public var page: Int?
    public var slot: Int?
    public var message: String?
    /// `reorder`：交换两个格子上的应用（0...8）
    public var from: Int?
    public var to: Int?
    /// `reorder` 跨页时目标页；缺省则与 `page` 同页。
    public var pageTo: Int?
    public var command: String?
    public var value: Double?
    /// Mac 端订阅是否在有效期内；随 `layout` 下发（Watch 桥接可转发；iOS 自身不再用其做门控）。
    public var subscriptionActive: Bool?
    /// Codex Micro 虚拟控制面：Agent 状态快照（也可编码在 `message` JSON 中）。
    public var agents: [HubCodexAgentSlot]?
    /// `input`：相对指针位移或滚轮。
    public var dx: Double?
    public var dy: Double?
    /// `input` 点击：`left` / `right`。
    public var button: String?
    /// `input` 按键名（见 `HubRemoteInputCommand`）。
    public var key: String?
    /// 随 `layout` 下发：当前 Mac 能否注入键鼠（官网 TreeletHub Pro 为 true）。
    public var remoteInputAvailable: Bool?

    public init(
        op: String,
        pin: String? = nil,
        deviceName: String? = nil,
        deviceId: String? = nil,
        ok: Bool? = nil,
        slots: [HubSlotConfig]? = nil,
        pages: [HubPageConfig]? = nil,
        page: Int? = nil,
        slot: Int? = nil,
        message: String? = nil,
        from: Int? = nil,
        to: Int? = nil,
        pageTo: Int? = nil,
        command: String? = nil,
        value: Double? = nil,
        subscriptionActive: Bool? = nil,
        agents: [HubCodexAgentSlot]? = nil,
        dx: Double? = nil,
        dy: Double? = nil,
        button: String? = nil,
        key: String? = nil,
        remoteInputAvailable: Bool? = nil
    ) {
        self.op = op
        self.pin = pin
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.ok = ok
        self.slots = slots
        self.pages = pages
        self.page = page
        self.slot = slot
        self.message = message
        self.from = from
        self.to = to
        self.pageTo = pageTo
        self.command = command
        self.value = value
        self.subscriptionActive = subscriptionActive
        self.agents = agents
        self.dx = dx
        self.dy = dy
        self.button = button
        self.key = key
        self.remoteInputAvailable = remoteInputAvailable
    }

    public static let opPair = "pair"
    public static let opPairResult = "pairResult"
    public static let opLayout = "layout"
    public static let opTap = "tap"
    public static let opError = "error"
    public static let opReorder = "reorder"
    public static let opDisconnect = "disconnect"
    public static let opControl = "control"
    /// iOS 主动请求 Mac 重发当前完整 layout（用于推送未达或 UI 未刷新时的定时/前台补偿）。
    public static let opRequestLayout = "requestLayout"
    /// iOS 多指滑动手势遥控 Mac 窗口/桌面（`command` 见 `HubGestureCommand`）。
    public static let opGesture = "gesture"
    /// iOS → Mac：虚拟 Codex Micro 控制指令（`message` 为 `HubCodexMicroCommand` JSON）。
    public static let opCodexMicro = "codexMicro"
    /// Mac → iOS：Codex Micro 实时状态（`message` 为 `HubCodexMicroState` JSON，`agents` 可同步下发）。
    public static let opCodexMicroState = "codexMicroState"
    /// 手机 → Mac：相对指针、点击、滚动与按键（仅 TreeletHub Pro 注入）。
    public static let opInput = "input"
}

/// 手机遥控 Mac 键鼠（随 `opInput` 的 `command` 字段发送）。
public enum HubRemoteInputCommand: String, Sendable {
    case move
    case click
    case scroll
    case keyDown
    case keyUp
    case text
    /// 按住拖移。`button` 为 `down` / `move` / `up`。
    case drag
    /// 双指捏合。`value` 是缩放增量，`button` 为 `began` / `changed` / `ended`。
    case magnify
    /// 双指旋转。`value` 是角度增量（度），`button` 为阶段。
    case rotate
    /// 双指轻点两下，智能缩放。
    case smartZoom
    /// 三指滑动。`key` 为 `up` / `down` / `left` / `right`。
    case swipe
    /// 三指轻点，查词 / 快速查看。
    case lookUp
}

/// iOS 遥控 Mac 的手势命令（随 `opGesture` 的 `command` 字段发送）。
public enum HubGestureCommand: String, Sendable {
    /// 隐藏全部已打开应用（含 TreeletHub）以显示桌面。
    case showDesktop = "showDesktop"
}

public enum HubWireCodec {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder = JSONDecoder()

    public static func encodeLine(_ envelope: HubWireEnvelope) throws -> Data {
        var data = try encoder.encode(envelope)
        data.append(10) // '\n'
        return data
    }

    public static func decodeLine(_ data: Data) throws -> HubWireEnvelope {
        try decoder.decode(HubWireEnvelope.self, from: data)
    }
}
