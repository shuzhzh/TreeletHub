import Combine
import Foundation
import StoreKit

/// iOS 端 StoreKit 订阅（需在 App Store Connect 配置与 Mac 不同的商品 ID）。
@MainActor
final class HubIOSSubscriptionManager: ObservableObject {
    nonisolated static let yearlyProductId = "com.treelet.treelethub.ios.pro.yearly"
    private static let cachedStatusKey = "treelethub.sub.ios.cached.active.v1"

    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        restoreCache()
        updatesTask = observeTransactionUpdates()
        Task {
            await refreshFromStore()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refreshFromStore() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        do {
            let products = try await Product.products(for: [Self.yearlyProductId])
            if let p = products.first(where: { $0.id == Self.yearlyProductId }) {
                yearlyProduct = p
            }
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.yearlyProductId else { continue }
            if transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
        persistCache()
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = update else { continue }
                if transaction.productID == Self.yearlyProductId {
                    isSubscribed = transaction.revocationDate == nil
                    persistCache()
                }
                await transaction.finish()
            }
        }
    }

    private func restoreCache() {
        isSubscribed = UserDefaults.standard.bool(forKey: Self.cachedStatusKey)
    }

    private func persistCache() {
        UserDefaults.standard.set(isSubscribed, forKey: Self.cachedStatusKey)
    }
}
