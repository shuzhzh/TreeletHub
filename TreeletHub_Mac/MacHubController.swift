import Combine
import SwiftUI

/// 将子 `ObservableObject` 的变更合并进来，否则 `ContentView` 只观察本类型时，`hub.grid` / `hub.pairing` 更新不会触发界面刷新。
@MainActor
final class MacHubController: ObservableObject {
    let pairing: HubPairingStore
    let grid: HubGridStore
    let server: HubMacServer
    let islandPresenter = HubIslandWindowPresenter()
    let keyboardHUDStore = HubKeyboardHUDStore()
    let keyboardHUDPresenter = HubKeyboardHUDPresenter()
    let typingSoundMonitor = HubTypingSoundMonitor()
    let codexMicro: HubCodexMicroBridge

    private var cancellables = Set<AnyCancellable>()

    init(subscription: HubSubscriptionManager) {
        let p = HubPairingStore()
        let g = HubGridStore()
        let micro = HubCodexMicroBridge()
        pairing = p
        grid = g
        codexMicro = micro
        server = HubMacServer(
            gridStore: g,
            pairingStore: p,
            isSubscriptionActive: { subscription.isSubscribed },
            codexMicro: micro
        )

        pairing.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        grid.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        server.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        keyboardHUDStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        keyboardHUDPresenter.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        micro.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        micro.start()
    }
}
