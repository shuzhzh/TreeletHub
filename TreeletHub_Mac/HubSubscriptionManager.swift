import Combine
import Foundation
import StoreKit

@MainActor
final class HubSubscriptionManager: ObservableObject {
    /// 一次性解锁 Pro（非消耗型）。
    nonisolated static let lifetimeProductId = "com.treelet.treelethub.mac.pro.lifetime"
    /// 旧年付订阅：已购用户继续视为已解锁。
    nonisolated static let legacyYearlyProductId = "com.treelet.treelethub.mac.pro.yearly"

    private static let allProductIds: Set<String> = [lifetimeProductId, legacyYearlyProductId]

    private static let cachedPriceKey = "treelethub.pro.cached.price.v2"
    private static let cachedTitleKey = "treelethub.pro.cached.title.v2"
    private static let cachedDescriptionKey = "treelethub.pro.cached.desc.v2"
    private static let cachedStatusKey = "treelethub.pro.cached.active.v2"

    @Published private(set) var lifetimeProduct: Product?
    /// 兼容旧命名：表示 Pro 已解锁（一次性或仍有效的旧订阅）。
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInFlight = false
    @Published var lastError: String?
    @Published private(set) var cachedPrice: String = ""
    @Published private(set) var cachedTitle: String = ""
    @Published private(set) var cachedDescription: String = ""

    /// 商店价；未拉取到时回退展示 $9.99。
    var displayTitle: String {
        lifetimeProduct?.displayName ?? (cachedTitle.isEmpty ? "" : cachedTitle)
    }

    var displayDescription: String {
        lifetimeProduct?.description ?? cachedDescription
    }

    var displayPrice: String {
        if let price = lifetimeProduct?.displayPrice, !price.isEmpty { return price }
        if !cachedPrice.isEmpty { return cachedPrice }
        return "$9.99"
    }

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
            let products = try await Product.products(for: Array(Self.allProductIds))
            if let p = products.first(where: { $0.id == Self.lifetimeProductId }) {
                lifetimeProduct = p
                cachedPrice = p.displayPrice
                cachedTitle = p.displayName
                cachedDescription = p.description
                persistCache()
            } else {
                lifetimeProduct = nil
            }
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        isSubscribed = await currentProUnlocked()
        persistCache()
    }

    func purchasePro() async {
        if lifetimeProduct == nil {
            await refreshFromStore()
        }
        guard let product = lifetimeProduct else {
            lastError = HubMacL10n.string("mac.subscription.err.no_products")
            return
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        lastError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = HubMacL10n.string("mac.subscription.err.verify_failed")
                    return
                }
                await transaction.finish()
                await refreshEntitlement()
            case .pending:
                lastError = HubMacL10n.string("mac.subscription.err.pending")
            case .userCancelled:
                break
            @unknown default:
                lastError = HubMacL10n.string("mac.subscription.err.unknown")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 旧调用名，转发到一次性购买。
    func purchaseYearly() async {
        await purchasePro()
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
        Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = update else { continue }
                if Self.allProductIds.contains(transaction.productID) {
                    await refreshEntitlement()
                }
                await transaction.finish()
            }
        }
    }

    private func restoreCache() {
        let defaults = UserDefaults.standard
        if let price = defaults.string(forKey: Self.cachedPriceKey), !price.isEmpty {
            cachedPrice = price
        }
        if let title = defaults.string(forKey: Self.cachedTitleKey), !title.isEmpty {
            cachedTitle = title
        }
        if let desc = defaults.string(forKey: Self.cachedDescriptionKey), !desc.isEmpty {
            cachedDescription = desc
        }
        // 兼容旧缓存键
        if defaults.object(forKey: Self.cachedStatusKey) == nil {
            isSubscribed = defaults.bool(forKey: "treelethub.sub.cached.active.v1")
        } else {
            isSubscribed = defaults.bool(forKey: Self.cachedStatusKey)
        }
    }

    private func persistCache() {
        let defaults = UserDefaults.standard
        defaults.set(cachedPrice, forKey: Self.cachedPriceKey)
        defaults.set(cachedTitle, forKey: Self.cachedTitleKey)
        defaults.set(cachedDescription, forKey: Self.cachedDescriptionKey)
        defaults.set(isSubscribed, forKey: Self.cachedStatusKey)
    }

    private func currentProUnlocked() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIds.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if transaction.productID == Self.legacyYearlyProductId {
                if let exp = transaction.expirationDate, exp < Date() {
                    continue
                }
            }
            return true
        }
        return false
    }
}
