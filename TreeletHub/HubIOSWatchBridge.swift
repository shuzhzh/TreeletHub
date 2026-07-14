import Combine
import Foundation
import UIKit
import WatchConnectivity

/// iPhone 侧 WatchConnectivity 桥：把 `HubIOSClient` 状态推给 Watch，并把 Watch 操作转回客户端。
@MainActor
final class HubIOSWatchBridge: NSObject, ObservableObject {
    static let shared = HubIOSWatchBridge()

    private weak var client: HubIOSClient?
    private var cancellables = Set<AnyCancellable>()
    private var lastMetaJSON: Data?
    private var lastIconFingerprints: [Int: Int] = [:]
    private var isActivated = false

    private override init() {
        super.init()
    }

    func attach(client: HubIOSClient) {
        guard self.client !== client else {
            publishSnapshot()
            return
        }
        self.client = client
        cancellables.removeAll()

        Publishers.MergeMany(
            client.$phase.map { _ in () }.eraseToAnyPublisher(),
            client.$pages.map { _ in () }.eraseToAnyPublisher(),
            client.$pinInput.map { _ in () }.eraseToAnyPublisher(),
            client.$lastError.map { _ in () }.eraseToAnyPublisher(),
            client.$didLoadCachedPairing.map { _ in () }.eraseToAnyPublisher(),
            client.$layoutApplyEpoch.map { _ in () }.eraseToAnyPublisher(),
            client.$serverReportsSubscriptionActive.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.publishSnapshot()
        }
        .store(in: &cancellables)

        activateSessionIfNeeded()
        publishSnapshot()
    }

    func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        if session.activationState != .activated, !isActivated {
            isActivated = true
            session.activate()
        } else if session.activationState == .activated {
            publishSnapshot()
        }
    }

    func publishSnapshot() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let client else { return }

        let meta = makeMetaSnapshot(from: client)
        guard let metaData = try? JSONEncoder().encode(meta) else { return }

        // 轻量状态始终走 applicationContext（无图标）。
        if metaData != lastMetaJSON {
            lastMetaJSON = metaData
            do {
                try session.updateApplicationContext([HubPhoneWatchSync.snapshotContextKey: metaData])
            } catch {}
            if session.isReachable {
                session.sendMessage(
                    [HubPhoneWatchSync.snapshotContextKey: metaData],
                    replyHandler: nil,
                    errorHandler: { _ in }
                )
            }
        }

        // 图标按页用原始 PNG Data 推送（不经 JSON Base64），体积小且保留透明通道。
        guard client.phase == .paired else {
            lastIconFingerprints.removeAll()
            return
        }
        let pages = Self.downsampledPages(client.pages)
        for page in pages {
            let fingerprint = Self.iconFingerprint(for: page)
            if lastIconFingerprints[page.id] == fingerprint { continue }
            var message: [String: Any] = [
                HubPhoneWatchSync.messageOpKey: HubPhoneWatchSync.MessageOp.iconsPage.rawValue,
                "page": page.id,
                "epoch": client.layoutApplyEpoch
            ]
            var hasIcon = false
            for slot in page.slots {
                if let icon = slot.iconPNG, !icon.isEmpty {
                    message["s\(slot.id)"] = icon
                    hasIcon = true
                }
            }
            guard hasIcon else {
                lastIconFingerprints[page.id] = fingerprint
                continue
            }
            deliverIconsMessage(message, pageId: page.id, fingerprint: fingerprint, session: session)
        }
    }

    private func deliverIconsMessage(
        _ message: [String: Any],
        pageId: Int,
        fingerprint: Int,
        session: WCSession
    ) {
        // 同时排队 transferUserInfo，避免仅依赖即时 sendMessage。
        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.lastIconFingerprints[pageId] = fingerprint
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    // 失败时清指纹，下次还会重试；transferUserInfo 可能仍会送达。
                    self?.lastIconFingerprints.removeValue(forKey: pageId)
                }
            })
        } else {
            lastIconFingerprints[pageId] = fingerprint
        }
    }

    private func makeMetaSnapshot(from client: HubIOSClient) -> HubWatchSyncSnapshot {
        let phase: HubPhoneWatchSync.Phase
        switch client.phase {
        case .idle: phase = .idle
        case .browsing: phase = .browsing
        case .connecting: phase = .connecting
        case .paired: phase = .paired
        }
        return HubWatchSyncSnapshot(
            phase: phase,
            pinInput: client.pinInput,
            lastError: client.lastError,
            didLoadCachedPairing: client.didLoadCachedPairing,
            pages: HubWatchSyncSnapshot.pagesWithoutIcons(client.pages),
            layoutApplyEpoch: client.layoutApplyEpoch,
            subscriptionActive: client.serverReportsSubscriptionActive,
            isPhoneReachable: true
        )
    }

    private static func iconFingerprint(for page: HubPageConfig) -> Int {
        var hasher = Hasher()
        hasher.combine(page.id)
        for slot in page.slots {
            hasher.combine(slot.id)
            hasher.combine(slot.bundleIdentifier)
            hasher.combine(slot.iconPNG?.count ?? 0)
            if let data = slot.iconPNG {
                hasher.combine(Data(data.prefix(32)))
            }
        }
        return hasher.finalize()
    }

    /// 缩到约 56×56 透明 PNG（Watch 支持 PNG；此前整包 JSON 过大才导致丢图标）。
    private static func downsampledPages(_ pages: [HubPageConfig]) -> [HubPageConfig] {
        pages.map { page in
            HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map { slot in
                    var s = slot
                    if let data = s.iconPNG, let tiny = downsampleIconPNG(data, maxSide: 56) {
                        s.iconPNG = tiny
                    } else {
                        s.iconPNG = nil
                    }
                    return s
                }
            )
        }
    }

    private static func downsampleIconPNG(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = rendered.pngData(), !png.isEmpty, png.count < 20_000 else { return nil }
        return png
    }

    private func handleWatchMessage(_ message: [String: Any]) {
        guard let client else { return }
        guard let opRaw = message[HubPhoneWatchSync.messageOpKey] as? String,
              let op = HubPhoneWatchSync.MessageOp(rawValue: opRaw)
        else { return }

        switch op {
        case .connectPin:
            if let pin = message["pin"] as? String {
                client.pinInput = pin
                client.connectUsingEnteredPin()
            }
        case .stopScanning:
            client.userStopScanning()
        case .disconnect:
            client.disconnect()
        case .tap:
            if let page = message["page"] as? Int, let slot = message["slot"] as? Int {
                client.tap(page: page, slot: slot)
            }
        case .control:
            let page = message["page"] as? Int
            let slot = message["slot"] as? Int
            let command = message["command"] as? String
            let value = message["value"] as? Double
            if let page, let slot {
                client.control(page: page, slot: slot, command: command, value: value)
            }
        case .requestSnapshot:
            lastIconFingerprints.removeAll()
            lastMetaJSON = nil
            publishSnapshot()
        case .iconsPage:
            break
        }
    }
}

extension HubIOSWatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.publishSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            session.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                self.lastIconFingerprints.removeAll()
            }
            self.publishSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleWatchMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.handleWatchMessage(message)
            replyHandler(["ok": true])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleWatchMessage(userInfo)
        }
    }
}
