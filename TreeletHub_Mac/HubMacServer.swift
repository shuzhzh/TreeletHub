import Combine
import Foundation
import Network

@MainActor
final class HubMacServer: ObservableObject {
    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()
    private var nextClientKey: UInt64 = 0

    private struct Client {
        var connection: NWConnection
        var buffer = Data()
        var paired = false
        var deviceName: String = "iPhone / iPad"
        var deviceId: String?
    }

    struct ConnectedDevice: Identifiable, Equatable {
        let id: UInt64
        let name: String
    }

    private var clients: [UInt64: Client] = [:]

    let gridStore: HubGridStore
    let pairingStore: HubPairingStore
    let codexMicro: HubCodexMicroBridge?
    /// 当前 Mac 订阅是否有效（由 HubSubscriptionManager 提供）。
    private let isSubscriptionActive: () -> Bool

    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?
    @Published private(set) var connectedDevices: [ConnectedDevice] = []

    init(
        gridStore: HubGridStore,
        pairingStore: HubPairingStore,
        isSubscriptionActive: @escaping () -> Bool = { false },
        codexMicro: HubCodexMicroBridge? = nil
    ) {
        self.gridStore = gridStore
        self.pairingStore = pairingStore
        self.isSubscriptionActive = isSubscriptionActive
        self.codexMicro = codexMicro

        pairingStore.$pin
            .dropFirst()
            .sink { [weak self] _ in
                self?.disconnectAllClients()
            }
            .store(in: &cancellables)

        gridStore.$pages
            .sink { [weak self] _ in
                self?.broadcastLayout()
            }
            .store(in: &cancellables)

        codexMicro?.onStateChange { [weak self] in
            self?.broadcastCodexMicroState()
        }
    }

    func start() {
        stop()
        lastError = nil
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            lastError = error.localizedDescription
            return
        }
        let name = Host.current().localizedName ?? "TreeletHub"
        listener.service = NWListener.Service(name: name, type: HubService.bonjourType)
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isListening = true
                case .failed(let err):
                    self.isListening = false
                    self.lastError = err.localizedDescription
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for id in clients.keys {
            clients[id]?.connection.cancel()
        }
        clients.removeAll()
        connectedDevices = []
        isListening = false
    }

    private func accept(_ connection: NWConnection) {
        let id = nextClientKey
        nextClientKey += 1
        clients[id] = Client(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed = state { self.removeClient(id) }
                if case .cancelled = state { self.removeClient(id) }
            }
        }
        connection.start(queue: .main)
        receiveNext(for: id)
    }

    private func removeClient(_ id: UInt64) {
        clients[id]?.connection.cancel()
        clients[id] = nil
        refreshConnectedDevices()
    }

    func disconnectDevice(_ id: UInt64) {
        send(.init(op: HubWireEnvelope.opDisconnect, message: "Mac与你断开连接"), to: id)
        removeClient(id)
    }

    private func disconnectAllClients() {
        for (id, _) in clients {
            removeClient(id)
        }
    }

    private func refreshConnectedDevices() {
        let pairedClients = clients
            .filter { $0.value.paired }
            .sorted { $0.key < $1.key }
        var counts: [String: Int] = [:]
        for (_, client) in pairedClients {
            counts[client.deviceName, default: 0] += 1
        }
        connectedDevices = pairedClients.map { id, client in
            let needsDisambiguation = (counts[client.deviceName] ?? 0) > 1
            let name: String
            if needsDisambiguation, let deviceId = client.deviceId, !deviceId.isEmpty {
                name = "\(client.deviceName) · \(String(deviceId.suffix(4)))"
            } else {
                name = client.deviceName
            }
            return ConnectedDevice(id: id, name: name)
        }
    }

    private func receiveNext(for id: UInt64) {
        guard clients[id] != nil else { return }
        clients[id]?.connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deliverReceive(clientId: id, data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func deliverReceive(clientId: UInt64, data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            // 与 `HubIOSClient` 一致：对端关 socket、切后台、Wi‑Fi 抖动等常见为 POSIX reset/abort，不应当成服务器故障刷屏。
            if !isTransientPeerDisconnect(error) {
                lastError = error.localizedDescription
            }
            removeClient(clientId)
            return
        }
        if let data, !data.isEmpty {
            clients[clientId]?.buffer.append(data)
            flushBuffer(for: clientId)
        }
        if isComplete {
            removeClient(clientId)
            return
        }
        receiveNext(for: clientId)
    }

    private func flushBuffer(for id: UInt64) {
        while var buf = clients[id]?.buffer, let nl = buf.firstIndex(of: 10) {
            let line = buf[..<nl]
            buf.removeSubrange(buf.startIndex...nl)
            clients[id]?.buffer = buf
            if !line.isEmpty {
                handleLine(Data(line), clientId: id)
            }
        }
    }

    private func handleLine(_ data: Data, clientId: UInt64) {
        let env: HubWireEnvelope
        do {
            env = try HubWireCodec.decodeLine(data)
        } catch {
            send(.init(op: HubWireEnvelope.opError, message: "无效的消息格式"), to: clientId)
            return
        }

        switch env.op {
        case HubWireEnvelope.opPair:
            guard let pin = env.pin else {
                send(.init(op: HubWireEnvelope.opError, message: "缺少 PIN"), to: clientId)
                return
            }
            let ok = pairingStore.verify(pin)
            clients[clientId]?.paired = ok
            if ok {
                let fallback = Self.endpointLabel(clients[clientId]?.connection.endpoint)
                let incoming = env.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let incomingDeviceId = env.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedDeviceId = (incomingDeviceId?.isEmpty == false ? incomingDeviceId : nil)
                clients[clientId]?.deviceId = normalizedDeviceId
                clients[clientId]?.deviceName = Self.makeDisplayDeviceName(
                    rawName: incoming,
                    fallback: fallback,
                    deviceId: normalizedDeviceId
                )
                removeDuplicatePairedClients(for: clientId)
            }
            refreshConnectedDevices()
            send(.init(op: HubWireEnvelope.opPairResult, ok: ok), to: clientId)
            if ok {
                sendLayout(to: clientId)
                sendCodexMicroState(to: clientId)
            }
        case HubWireEnvelope.opTap:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            guard let page = env.page,
                  let pageData = gridStore.pages.first(where: { $0.id == page })
            else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的页面"), to: clientId)
                return
            }
            guard let slot = env.slot, (0..<9).contains(slot) else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的格子"), to: clientId)
                return
            }
            let config = pageData.slots[slot]
            Task {
                do {
                    if config.kind == .shortcut {
                        guard let shortcut = config.shortcutKind else {
                            throw NSError(domain: "TreeletHub", code: 2001, userInfo: [NSLocalizedDescriptionKey: "该快捷操作配置无效"])
                        }
                        try await MacAppActivator.performShortcut(shortcut, payload: config.shortcutPayload, value: nil)
                    } else {
                        guard let bid = config.bundleIdentifier, !bid.isEmpty else {
                            throw NSError(domain: "TreeletHub", code: 2000, userInfo: [NSLocalizedDescriptionKey: "该格未配置应用"])
                        }
                        let bookmark = gridStore.bindingURL(for: bid)
                        try await MacAppActivator.activate(bundleIdentifier: bid, bookmarkURL: bookmark)
                    }
                } catch {
                    await MainActor.run {
                        self.send(.init(op: HubWireEnvelope.opError, message: error.localizedDescription), to: clientId)
                    }
                }
            }
        case HubWireEnvelope.opControl:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            guard let page = env.page,
                  let pageData = gridStore.pages.first(where: { $0.id == page }),
                  let slot = env.slot,
                  (0..<9).contains(slot)
            else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的控制目标"), to: clientId)
                return
            }
            let config = pageData.slots[slot]
            guard config.kind == .shortcut, let shortcut = config.shortcutKind else {
                send(.init(op: HubWireEnvelope.opError, message: "该格不是快捷操作"), to: clientId)
                return
            }
            Task {
                do {
                    try await MacAppActivator.performShortcut(shortcut, payload: env.command ?? config.shortcutPayload, value: env.value)
                } catch {
                    await MainActor.run {
                        self.send(.init(op: HubWireEnvelope.opError, message: error.localizedDescription), to: clientId)
                    }
                }
            }
        case HubWireEnvelope.opReorder:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            guard let page = env.page,
                  gridStore.pages.contains(where: { $0.id == page })
            else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的页面"), to: clientId)
                return
            }
            guard let from = env.from, let to = env.to,
                  (0..<9).contains(from), (0..<9).contains(to), from != to
            else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的交换参数"), to: clientId)
                return
            }
            gridStore.swapSlots(page: page, at: from, j: to)
        case HubWireEnvelope.opRequestLayout:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            sendLayout(to: clientId)
        case HubWireEnvelope.opGesture:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            let command = env.command ?? ""
            let gesture: HubGestureCommand?
            if let parsed = HubGestureCommand(rawValue: command) {
                gesture = parsed
            } else if command == "minimizeFront" {
                // 兼容旧版 iOS：原双指命令统一为显示桌面。
                gesture = .showDesktop
            } else {
                gesture = nil
            }
            guard let gesture else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的手势命令"), to: clientId)
                return
            }
            Task {
                do {
                    try await MacAppActivator.performGesture(gesture)
                } catch {
                    await MainActor.run {
                        self.send(.init(op: HubWireEnvelope.opError, message: error.localizedDescription), to: clientId)
                    }
                }
            }
        case HubWireEnvelope.opCodexMicro:
            guard clients[clientId]?.paired == true else {
                send(.init(op: HubWireEnvelope.opError, message: "未配对"), to: clientId)
                return
            }
            guard let bridge = codexMicro else {
                send(.init(op: HubWireEnvelope.opError, message: "Codex Micro 不可用"), to: clientId)
                return
            }
            guard let command = HubCodexMicroWire.decodeCommand(env.message) else {
                send(.init(op: HubWireEnvelope.opError, message: "无效的 Codex Micro 指令"), to: clientId)
                return
            }
            Task {
                do {
                    try await bridge.handle(command)
                    await MainActor.run {
                        self.sendCodexMicroState(to: clientId)
                    }
                } catch {
                    await MainActor.run {
                        self.send(.init(op: HubWireEnvelope.opError, message: error.localizedDescription), to: clientId)
                    }
                }
            }
        default:
            send(.init(op: HubWireEnvelope.opError, message: "unsupportedOp:\(env.op)"), to: clientId)
        }
    }

    private func send(_ envelope: HubWireEnvelope, to clientId: UInt64) {
        guard let data = try? HubWireCodec.encodeLine(envelope) else { return }
        guard let conn = clients[clientId]?.connection else { return }
        conn.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    private func sendLayout(to clientId: UInt64) {
        let env = HubWireEnvelope(
            op: HubWireEnvelope.opLayout,
            pages: gridStore.pagesForWire(),
            subscriptionActive: isSubscriptionActive()
        )
        send(env, to: clientId)
    }

    private func sendCodexMicroState(to clientId: UInt64) {
        guard let bridge = codexMicro else { return }
        send(bridge.snapshotEnvelope(), to: clientId)
    }

    private func broadcastCodexMicroState() {
        guard let bridge = codexMicro else { return }
        guard let data = try? HubWireCodec.encodeLine(bridge.snapshotEnvelope()) else { return }
        for id in clients.keys {
            guard clients[id]?.paired == true else { continue }
            clients[id]?.connection.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
        }
    }

    private func broadcastLayout() {
        guard let data = try? HubWireCodec.encodeLine(
            HubWireEnvelope(
                op: HubWireEnvelope.opLayout,
                pages: gridStore.pagesForWire(),
                subscriptionActive: isSubscriptionActive()
            )
        ) else { return }
        for id in clients.keys {
            guard clients[id]?.paired == true else { continue }
            clients[id]?.connection.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
        }
    }

    /// 订阅状态等变更时向已配对客户端重发 layout（刷新 `subscriptionActive`）。
    func publishLayoutToPairedClients() {
        broadcastLayout()
    }

    /// 客户端正常或异常断线时，`receive` 常回报 `ECONNRESET`(54) 等；与布局广播等活动同时出现时易被误判为「添加 App 出错」。
    private func isTransientPeerDisconnect(_ error: NWError) -> Bool {
        if case .posix(let code) = error {
            switch code {
            case .ECONNABORTED, .ECONNRESET, .ENOTCONN, .ECONNREFUSED, .EPIPE, .ETIMEDOUT:
                return true
            default:
                break
            }
        }
        if case .tls = error { return true }
        return false
    }

    private static func endpointLabel(_ endpoint: NWEndpoint?) -> String {
        guard let endpoint else { return "iPhone / iPad" }
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        case .hostPort(let host, _):
            return "\(host)"
        default:
            return "iPhone / iPad"
        }
    }

    private static func makeDisplayDeviceName(rawName: String?, fallback: String, deviceId: String?) -> String {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed?.isEmpty == false ? trimmed! : fallback)
        let lower = base.lowercased()
        let isGeneric = lower == "iphone" || lower == "ipad" || lower == "iphone / ipad"
        guard isGeneric else { return base }
        guard let deviceId, !deviceId.isEmpty else { return base }
        let suffix = String(deviceId.suffix(4))
        return "\(base) · \(suffix)"
    }

    /// 同一设备重连时，保留最新连接，移除旧连接，避免设备列表出现重复条目。
    private func removeDuplicatePairedClients(for currentClientId: UInt64) {
        guard let currentDeviceId = clients[currentClientId]?.deviceId, !currentDeviceId.isEmpty else { return }
        let duplicates: [UInt64] = clients
            .filter { id, client in
                id != currentClientId && client.paired && client.deviceId == currentDeviceId
            }
            .map(\.key)
        for id in duplicates {
            clients[id]?.connection.cancel()
            clients[id] = nil
        }
    }
}
