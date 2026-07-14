import Combine
import Foundation
import WatchConnectivity

/// Watch 侧：镜像 iPhone 连接状态，并把配对/点按等操作发给 iPhone。
@MainActor
final class HubWatchCompanion: NSObject, ObservableObject {
    static let shared = HubWatchCompanion()

    @Published private(set) var snapshot = HubWatchSyncSnapshot()
    @Published var pinInput: String = ""
    @Published private(set) var isSessionActivated = false
    @Published private(set) var lastLocalError: String?

    private var isActivating = false
    private var lastIconRequestAt: Date?
    /// 图标可能先于布局快照到达；暂存后在 `applySnapshot` 时合并。
    private var pendingIconsByPage: [Int: [Int: Data]] = [:]

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastLocalError = HubWatchL10n.string("watch.error.session_unsupported")
            return
        }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        if session.activationState == .activated {
            isSessionActivated = true
            applyReceivedContext(session.receivedApplicationContext)
            requestSnapshotFromPhone()
            return
        }
        guard !isActivating else { return }
        isActivating = true
        session.activate()
    }

    var phase: HubPhoneWatchSync.Phase { snapshot.phase }
    var pages: [HubPageConfig] { snapshot.pages }
    var isPaired: Bool { snapshot.phase == .paired }
    var isBusy: Bool { snapshot.phase == .browsing || snapshot.phase == .connecting }
    var isPhoneAppReachable: Bool { WCSession.default.isReachable || snapshot.isPhoneReachable }

    func appendPinDigit(_ digit: String) {
        guard pinInput.count < 6 else { return }
        pinInput.append(contentsOf: digit.filter(\.isNumber))
        if pinInput.count > 6 {
            pinInput = String(pinInput.prefix(6))
        }
    }

    func deletePinDigit() {
        guard !pinInput.isEmpty else { return }
        pinInput.removeLast()
    }

    func clearPin() {
        pinInput = ""
    }

    func connectUsingEnteredPin() {
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            lastLocalError = HubWatchL10n.string("watch.error.pin_format")
            return
        }
        lastLocalError = nil
        // 本地乐观显示「连接中」，等 iPhone 回推真实状态。
        var optimistic = snapshot
        optimistic.phase = .browsing
        optimistic.pinInput = pin
        optimistic.lastError = nil
        snapshot = optimistic
        send([
            HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.connectPin.rawValue,
            "pin": pin
        ])
    }

    func stopScanning() {
        send([HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.stopScanning.rawValue])
    }

    func disconnect() {
        send([HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.disconnect.rawValue])
    }

    func tap(page: Int, slot: Int) {
        guard isPaired else { return }
        send([
            HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.tap.rawValue,
            "page": page,
            "slot": slot
        ])
    }

    func control(page: Int, slot: Int, command: String? = nil, value: Double? = nil) {
        guard isPaired else { return }
        var msg: [String: Any] = [
            HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.control.rawValue,
            "page": page,
            "slot": slot
        ]
        if let command { msg["command"] = command }
        if let value { msg["value"] = value }
        send(msg)
    }

    func requestSnapshotFromPhone() {
        send([HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.requestSnapshot.rawValue])
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastLocalError = HubWatchL10n.string("watch.error.open_iphone")
            return
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.lastLocalError = nil
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.lastLocalError = error.localizedDescription
                }
            })
        } else {
            // iPhone 未前台时用 transferUserInfo 排队投递，仍依赖手机执行真实连接。
            session.transferUserInfo(message)
            lastLocalError = HubWatchL10n.string("watch.error.iphone_unreachable")
        }
    }

    private func applyReceivedContext(_ context: [String: Any]) {
        if let icons = HubPhoneWatchSync.parseIconsPage(context) {
            applyIconsPage(page: icons.page, epoch: icons.epoch, icons: icons.icons)
            return
        }
        guard let data = context[HubPhoneWatchSync.snapshotContextKey] as? Data,
              let decoded = try? JSONDecoder().decode(HubWatchSyncSnapshot.self, from: data)
        else { return }
        applySnapshot(decoded)
    }

    private func applyIconsPage(page pageId: Int, epoch: UInt64, icons: [Int: Data]) {
        guard !icons.isEmpty else { return }
        var next = snapshot
        if !next.pages.contains(where: { $0.id == pageId }) {
            pendingIconsByPage[pageId] = icons
            requestSnapshotFromPhone()
            return
        }
        pendingIconsByPage.removeValue(forKey: pageId)
        next.applyIcons(page: pageId, icons: icons)
        next.isPhoneReachable = WCSession.default.isReachable
        snapshot = next
    }

    private func applySnapshot(_ incoming: HubWatchSyncSnapshot) {
        var next = incoming
        next.isPhoneReachable = WCSession.default.isReachable
        // applicationContext 可能只带无图标的轻量快照；不要覆盖已有的图标包。
        if !next.hasAnyIcon, snapshot.hasAnyIcon {
            next.pages = Self.mergingIcons(from: snapshot.pages, onto: next.pages)
        }
        // 合并早到的图标页。
        if !pendingIconsByPage.isEmpty {
            for (pageId, icons) in pendingIconsByPage {
                next.applyIcons(page: pageId, icons: icons)
            }
            pendingIconsByPage = pendingIconsByPage.filter { pageId, _ in
                !next.pages.contains(where: { $0.id == pageId })
            }
        }
        snapshot = next
        // 未配对时用服务端/手机侧缓存的 PIN 预填数字盘（用户可改）。
        if next.phase != .paired, !next.pinInput.isEmpty, pinInput.isEmpty {
            pinInput = next.pinInput
        }
        if next.phase == .paired || next.phase == .browsing || next.phase == .connecting {
            lastLocalError = nil
        }
        if let err = next.lastError, !err.isEmpty {
            lastLocalError = err
        }
        // 布局到了但还没图标时，限流后主动跟 iPhone 再要一次。
        if next.phase == .paired, !next.hasAnyIcon {
            let now = Date()
            if lastIconRequestAt == nil || now.timeIntervalSince(lastIconRequestAt!) > 2.5 {
                lastIconRequestAt = now
                requestSnapshotFromPhone()
            }
        }
    }

    /// 把旧快照里的图标合并进新布局（按 page/slot 与 bundleIdentifier 对齐）。
    private static func mergingIcons(from oldPages: [HubPageConfig], onto newPages: [HubPageConfig]) -> [HubPageConfig] {
        let oldByPage = Dictionary(uniqueKeysWithValues: oldPages.map { ($0.id, $0) })
        return newPages.map { page in
            guard let oldPage = oldByPage[page.id] else { return page }
            let oldBySlot = Dictionary(uniqueKeysWithValues: oldPage.slots.map { ($0.id, $0) })
            return HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map { slot in
                    var s = slot
                    if s.iconPNG == nil,
                       let old = oldBySlot[slot.id],
                       old.iconPNG != nil,
                       old.bundleIdentifier == s.bundleIdentifier,
                       old.kind == s.kind,
                       old.shortcutKind == s.shortcutKind
                    {
                        s.iconPNG = old.iconPNG
                    }
                    return s
                }
            )
        }
    }
}

extension HubWatchCompanion: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isActivating = false
            self.isSessionActivated = activationState == .activated
            if let error {
                self.lastLocalError = error.localizedDescription
            }
            if activationState == .activated {
                self.applyReceivedContext(session.receivedApplicationContext)
                self.requestSnapshotFromPhone()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            var next = self.snapshot
            next.isPhoneReachable = session.isReachable
            self.snapshot = next
            if session.isReachable {
                self.lastLocalError = nil
                self.requestSnapshotFromPhone()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(message)
        }
    }

    /// iPhone 使用带 `replyHandler` 的 `sendMessage` 推图标时，必须实现此方法，
    /// 否则系统会报 “does not implement delegate method” 并丢弃消息。
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // 先立即回复，避免超时；再异步应用内容。
        replyHandler(["ok": true])
        Task { @MainActor in
            self.applyReceivedContext(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.applyReceivedContext(userInfo)
        }
    }
}

enum HubWatchL10n {
    static func string(_ key: String) -> String {
        let id = Locale.preferredLanguages.first ?? "en"
        let locale: Locale
        if id.hasPrefix("zh-Hans") || id.hasPrefix("zh-CN") || id.lowercased().hasPrefix("zh-cn") {
            locale = Locale(identifier: "zh-Hans")
        } else {
            locale = Locale(identifier: "en")
        }
        return HubBundleLocalizedString.localized(key, locale: locale, bundle: .main)
    }
}
