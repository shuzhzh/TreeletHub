import Combine
import Foundation
import Network
import UIKit

@MainActor
final class HubIOSClient: ObservableObject {
    static let customDeviceNameDefaultsKey = "treelethub.device.displayName"

    enum Phase: Equatable {
        case idle
        case browsing
        case connecting
        case paired
    }

    @Published var phase: Phase = .idle
    @Published var services: [NWBrowser.Result] = []
    @Published var pages: [HubPageConfig] = [HubPageConfig(id: 0, title: "Apps")]
    /// 每次应用服务端 `layout` 后递增；用于 SwiftUI `.id` 强制刷新九宫格（否则 `TabView`/`LazyVGrid` 常按稳定的 page/slot `id` 复用视图，Mac 更新应用/快捷方式后界面仍显示旧内容）。
    @Published private(set) var layoutApplyEpoch: UInt64 = 0
    /// Mac 在 layout 中报告的订阅是否有效（与 iOS 本地 StoreKit  entitlement 共同决定是否展示多页 Tab）。
    @Published private(set) var serverReportsSubscriptionActive = false
    @Published var pinInput: String = ""
    /// 仅在非静默流程下向用户展示（配对界面）。
    @Published var lastError: String?
    @Published var serverDisconnectAlertMessage: String?
    @Published private(set) var didLoadCachedPairing = false

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()

    private var pendingBonjourName: String?
    private var cachedBonjourNameForRestore: String?
    /// 扫描到服务后自动 `connect`（手动输入配对码或恢复缓存时均为 true）。
    private var wantsAutoConnectAfterBrowse = false
    /// 当前连接/重连尝试是否不向用户展示错误（启动恢复、回到前台自动重连）。
    private var isSilentReconnect = false
    /// 防止 `receive` 报错或对端关流后反复静默重连打爆 Bonjour。
    private var lastSilentReceiveReconnectAt: Date?
    /// 已配对时周期性向 Mac 请求 `layout`，补偿单向推送偶发未刷新。
    private var layoutPullHeartbeatTask: Task<Void, Never>?

    // MARK: - 启动 / 前台静默重连

    func restorePairingFromDiskOnLaunch() {
        guard let data = UserDefaults.standard.data(forKey: HubPairingCache.userDefaultsKey),
              let cache = try? JSONDecoder().decode(HubPairingCache.self, from: data)
        else { return }
        pinInput = cache.pin
        cachedBonjourNameForRestore = cache.bonjourServiceName
        didLoadCachedPairing = true
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        startBrowsing()
    }

    /// App 回到前台：若已配对则立刻向 Mac 拉一次 layout；若未连接则按缓存静默重连。
    func reconnectFromCacheIfNeededOnForeground() {
        if phase == .paired {
            sendRequestLayoutToMac()
            return
        }
        guard phase != .browsing, phase != .connecting else { return }
        guard let data = UserDefaults.standard.data(forKey: HubPairingCache.userDefaultsKey),
              let cache = try? JSONDecoder().decode(HubPairingCache.self, from: data)
        else { return }
        pinInput = cache.pin
        cachedBonjourNameForRestore = cache.bonjourServiceName
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        startBrowsing()
    }

    // MARK: - 扫描（不重置自动连接意图）

    func startBrowsing() {
        tearDownBrowserOnly()
        if !isSilentReconnect { lastError = nil }
        phase = .browsing
        let browser = NWBrowser(
            for: .bonjour(type: HubService.bonjourType, domain: HubService.bonjourDomain),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed(let e) = state {
                    self.reportBrowserFailure(e)
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.services = Array(results)
                self.tryAutoConnectIfNeeded()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// 用户输入配对码后：自动发现并连接第一台 Mac（或缓存主机名）。
    func connectUsingEnteredPin() {
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            lastError = HubIOSL10n.string("ios.error.pin_format")
            return
        }
        isSilentReconnect = false
        wantsAutoConnectAfterBrowse = true
        cachedBonjourNameForRestore = nil
        startBrowsing()
    }

    func userStopScanning() {
        tearDownBrowserOnly()
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
        if phase == .browsing || phase == .connecting { phase = .idle }
    }

    func disconnect() {
        cancelLayoutPullHeartbeat()
        tearDownBrowserOnly()
        connection?.cancel()
        connection = nil
        buffer = Data()
        phase = .idle
        pendingBonjourName = nil
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
        UserDefaults.standard.removeObject(forKey: HubPairingCache.userDefaultsKey)
        cachedBonjourNameForRestore = nil
        serverDisconnectAlertMessage = nil
        serverReportsSubscriptionActive = false
    }

    /// 仅断开当前连接并返回配对页，不清理缓存配对码。
    func returnToPairingAfterServerDisconnect() {
        cancelLayoutPullHeartbeat()
        tearDownBrowserOnly()
        connection?.cancel()
        connection = nil
        buffer = Data()
        phase = .idle
        pendingBonjourName = nil
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
        serverDisconnectAlertMessage = nil
        serverReportsSubscriptionActive = false
    }

    private func tearDownBrowserOnly() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - 连接

    func connect(to result: NWBrowser.Result) {
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            if !isSilentReconnect { lastError = HubIOSL10n.string("ios.error.pin_format") }
            return
        }

        cancelLayoutPullHeartbeat()
        connection?.cancel()
        connection = nil
        buffer = Data()
        tearDownBrowserOnly()
        wantsAutoConnectAfterBrowse = false

        if !isSilentReconnect {
            lastError = nil
        }
        phase = .connecting
        pendingBonjourName = Self.endpointLabel(result.endpoint)

        let conn = NWConnection(to: result.endpoint, using: NWParameters.tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendPair(pin: pin)
                case .failed(let e):
                    self.reportConnectionFailure(e)
                case .cancelled:
                    if self.phase != .paired { self.phase = .idle }
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        receiveNext()
    }

    private func tryAutoConnectIfNeeded() {
        guard wantsAutoConnectAfterBrowse, phase == .browsing else { return }
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        guard !services.isEmpty else { return }

        let sorted = services.sorted {
            Self.endpointLabel($0.endpoint) < Self.endpointLabel($1.endpoint)
        }
        let pick: NWBrowser.Result?
        if let name = cachedBonjourNameForRestore,
           let match = sorted.first(where: { Self.endpointLabel($0.endpoint) == name }) {
            pick = match
        } else {
            pick = sorted.first
        }
        guard let target = pick else { return }

        wantsAutoConnectAfterBrowse = false
        connect(to: target)
    }

    private func savePairingToDisk() {
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 6 else { return }
        let cache = HubPairingCache(pin: pin, bonjourServiceName: pendingBonjourName)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: HubPairingCache.userDefaultsKey)
        }
    }

    private func sendPair(pin: String) {
        let stableDeviceId =
            UIDevice.current.identifierForVendor?.uuidString ??
            "\(UIDevice.current.name)-\(UIDevice.current.model)"
        let reportedName = resolvedReportedDeviceName()
        let env = HubWireEnvelope(
            op: HubWireEnvelope.opPair,
            pin: pin,
            deviceName: reportedName,
            deviceId: stableDeviceId
        )
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    private func resolvedReportedDeviceName() -> String {
        if let custom = UserDefaults.standard.string(forKey: Self.customDeviceNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty
        {
            return custom
        }
        return UIDevice.current.name
    }

    func tap(page: Int, slot: Int) {
        guard phase == .paired else { return }
        let env = HubWireEnvelope(op: HubWireEnvelope.opTap, page: page, slot: slot)
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    /// 与另一格交换位置（由 Mac 更新权威状态并广播 layout）。
    func reorder(page: Int, from: Int, to: Int) {
        guard phase == .paired else { return }
        guard (0..<9).contains(from), (0..<9).contains(to), from != to else { return }
        let env = HubWireEnvelope(op: HubWireEnvelope.opReorder, page: page, from: from, to: to)
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    func control(page: Int, slot: Int, command: String? = nil, value: Double? = nil) {
        guard phase == .paired else { return }
        let env = HubWireEnvelope(op: HubWireEnvelope.opControl, page: page, slot: slot, command: command, value: value)
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    /// 多指滑动手势（最小化前台窗口 / 显示桌面等）。
    func gesture(command: HubGestureCommand) {
        guard phase == .paired else { return }
        let env = HubWireEnvelope(op: HubWireEnvelope.opGesture, command: command.rawValue)
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    // MARK: - 错误（静默时吞掉常见断线）

    private func reportBrowserFailure(_ error: NWError) {
        if isSilentReconnect, isTransientNWError(error) { return }
        lastError = error.localizedDescription
    }

    private func reportConnectionFailure(_ error: NWError) {
        if isSilentReconnect, isTransientNWError(error) {
            phase = .idle
            endSilentIfNeeded()
            return
        }
        lastError = error.localizedDescription
        phase = .idle
        endSilentIfNeeded()
    }

    private func reportReceiveFailure(_ error: NWError) {
        if phase == .paired, isTransientNWError(error) {
            return
        }
        if isSilentReconnect, isTransientNWError(error) {
            return
        }
        lastError = error.localizedDescription
    }

    /// POSIX 53 = `ECONNABORTED`（Software caused connection abort）等，常见于后台断连、对端关闭。
    private func isTransientNWError(_ error: NWError) -> Bool {
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

    private func endSilentIfNeeded() {
        if isSilentReconnect {
            isSilentReconnect = false
        }
    }

    /// `receive` 回调出错或 `isComplete` 时若仍显示已配对，原先会直接 `return` 且不再 `receiveNext`，TCP 上后续 layout 永远不会被读，表现为「Mac 改了要等断开重连才同步」。
    private func scheduleSilentReconnectAfterReceiveLoss() {
        let now = Date()
        if let t = lastSilentReceiveReconnectAt, now.timeIntervalSince(t) < 1.2 { return }
        lastSilentReceiveReconnectAt = now

        cancelLayoutPullHeartbeat()
        lastError = nil
        tearDownBrowserOnly()
        connection?.cancel()
        connection = nil
        buffer = Data()
        pendingBonjourName = nil
        phase = .idle
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        if let data = UserDefaults.standard.data(forKey: HubPairingCache.userDefaultsKey),
           let cache = try? JSONDecoder().decode(HubPairingCache.self, from: data)
        {
            cachedBonjourNameForRestore = cache.bonjourServiceName
        }
        startBrowsing()
    }

    private func cancelLayoutPullHeartbeat() {
        layoutPullHeartbeatTask?.cancel()
        layoutPullHeartbeatTask = nil
    }

    /// 已配对时约每 8 秒向 Mac 请求一次完整 layout，与 Mac 主动广播互补。
    private func startLayoutPullHeartbeat() {
        cancelLayoutPullHeartbeat()
        layoutPullHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self, self.phase == .paired else { break }
                self.sendRequestLayoutToMac()
            }
        }
    }

    private func sendRequestLayoutToMac() {
        guard phase == .paired else { return }
        let env = HubWireEnvelope(op: HubWireEnvelope.opRequestLayout)
        guard let data = try? HubWireCodec.encodeLine(env) else { return }
        connection?.send(content: data, isComplete: false, completion: .contentProcessed { _ in })
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deliverReceive(data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func deliverReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            reportReceiveFailure(error)
            if phase == .paired {
                scheduleSilentReconnectAfterReceiveLoss()
            } else {
                phase = .idle
                endSilentIfNeeded()
            }
            return
        }
        if let data, !data.isEmpty {
            buffer.append(data)
            flushBuffer()
        }
        if isComplete {
            if phase == .paired {
                scheduleSilentReconnectAfterReceiveLoss()
            } else {
                if phase != .paired { phase = .idle }
                endSilentIfNeeded()
            }
            return
        }
        receiveNext()
    }

    private func flushBuffer() {
        while let nl = buffer.firstIndex(of: 10) {
            let line = buffer[..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty {
                handleLine(Data(line))
            }
        }
    }

    private func normalizePages(_ raw: [HubPageConfig]) -> [HubPageConfig] {
        raw.sorted { $0.id < $1.id }.map { page in
            let slots = page.slots.sorted { $0.id < $1.id }.map { slot in
                var s = slot
                if let icon = s.iconPNG, icon.isEmpty { s.iconPNG = nil }
                return s
            }
            return HubPageConfig(id: page.id, title: page.title, slots: slots)
        }
    }

    private func handleLine(_ data: Data) {
        let env: HubWireEnvelope
        do {
            env = try HubWireCodec.decodeLine(data)
        } catch {
            if !isSilentReconnect { lastError = HubIOSL10n.string("ios.error.parse_message") }
            return
        }
        switch env.op {
        case HubWireEnvelope.opPairResult:
            if env.ok == true {
                phase = .paired
                savePairingToDisk()
                pendingBonjourName = nil
                endSilentIfNeeded()
                startLayoutPullHeartbeat()
            } else {
                if !isSilentReconnect { lastError = HubIOSL10n.string("ios.error.wrong_pin") }
                phase = .idle
                connection?.cancel()
                cancelLayoutPullHeartbeat()
                endSilentIfNeeded()
            }
        case HubWireEnvelope.opLayout:
            serverReportsSubscriptionActive = env.subscriptionActive ?? false
            if let p = env.pages, !p.isEmpty {
                pages = normalizePages(p)
            } else if let s = env.slots, s.count == 9 {
                // 兼容旧服务端：单页布局。
                pages = [HubPageConfig(id: 0, title: "Apps", slots: s)]
            }
            layoutApplyEpoch &+= 1
        case HubWireEnvelope.opError:
            if phase == .paired, let m = env.message,
               m == "未知操作" || m.hasPrefix("unsupportedOp:")
            {
                // 旧版 Mac 不识别 `requestLayout` 等扩展指令时会回此类错误；已配对时多为心跳探测，避免刷屏。
                break
            }
            if !isSilentReconnect {
                lastError = env.message ?? HubIOSL10n.string("ios.error.unknown")
            }
        case HubWireEnvelope.opDisconnect:
            serverDisconnectAlertMessage = env.message
            cancelLayoutPullHeartbeat()
            tearDownBrowserOnly()
            connection?.cancel()
            connection = nil
            buffer = Data()
            phase = .idle
            pendingBonjourName = nil
            wantsAutoConnectAfterBrowse = false
            isSilentReconnect = false
            serverReportsSubscriptionActive = false
        default:
            break
        }
    }

    static func endpointLabel(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return "TreeletHub"
        }
    }
}
