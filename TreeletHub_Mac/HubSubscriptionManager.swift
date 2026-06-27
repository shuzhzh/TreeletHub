import Combine
import Foundation
import StoreKit

@MainActor
final class HubSubscriptionManager: ObservableObject {
    nonisolated static let yearlyProductId = "com.treelet.treelethub.mac.pro.yearly"
    private static let cachedPriceKey = "treelethub.sub.cached.price.v1"
    private static let cachedTitleKey = "treelethub.sub.cached.title.v1"
    private static let cachedDescriptionKey = "treelethub.sub.cached.desc.v1"
    private static let cachedStatusKey = "treelethub.sub.cached.active.v1"
    private static let cachedExpirationKey = "treelethub.sub.cached.expiration.v1"
    private static let cachedAtKey = "treelethub.sub.cached.at.v1"

    private static let expirationCacheFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var isSubscribed = false
    /// 当前有效订阅的到期时间（自动续订成功后会顺延）；未订阅或非订阅类交易为 `nil`。
    @Published private(set) var subscriptionExpirationDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInFlight = false
    @Published var lastError: String?
    @Published private(set) var cachedPrice: String = ""
    @Published private(set) var cachedTitle: String = ""
    @Published private(set) var cachedDescription: String = ""

    var displayTitle: String {
        yearlyProduct?.displayName ?? cachedTitle
    }

    var displayDescription: String {
        yearlyProduct?.description ?? cachedDescription
    }

    var displayPrice: String {
        yearlyProduct?.displayPrice ?? cachedPrice
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
            let products = try await Product.products(for: [Self.yearlyProductId])
            if let p = products.first(where: { $0.id == Self.yearlyProductId }) {
                yearlyProduct = p
                cachedPrice = p.displayPrice
                cachedTitle = p.displayName
                cachedDescription = p.description
                persistCache()
            }
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        let snapshot = await currentEntitlementSnapshot()
        isSubscribed = snapshot.active
        subscriptionExpirationDate = snapshot.active ? snapshot.expiration : nil
        persistCache()
    }

    func purchaseYearly() async {
        guard let product = yearlyProduct else {
            lastError = HubMacL10n.string("mac.subscription.err.no_products")
            return
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
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
                if transaction.productID == Self.yearlyProductId {
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
        isSubscribed = defaults.bool(forKey: Self.cachedStatusKey)
        if isSubscribed,
           let expStr = defaults.string(forKey: Self.cachedExpirationKey),
           let d = Self.expirationCacheFormatter.date(from: expStr)
               ?? ISO8601DateFormatter().date(from: expStr)
        {
            subscriptionExpirationDate = d
        } else {
            subscriptionExpirationDate = nil
        }
    }

    private func persistCache() {
        let defaults = UserDefaults.standard
        defaults.set(cachedPrice, forKey: Self.cachedPriceKey)
        defaults.set(cachedTitle, forKey: Self.cachedTitleKey)
        defaults.set(cachedDescription, forKey: Self.cachedDescriptionKey)
        defaults.set(isSubscribed, forKey: Self.cachedStatusKey)
        if let subscriptionExpirationDate {
            defaults.set(Self.expirationCacheFormatter.string(from: subscriptionExpirationDate), forKey: Self.cachedExpirationKey)
        } else {
            defaults.removeObject(forKey: Self.cachedExpirationKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Self.cachedAtKey)
    }

    /// 汇总当前权益：是否仍在订阅期内、最晚到期时间。
    private func currentEntitlementSnapshot() async -> (active: Bool, expiration: Date?) {
        var active = false
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.yearlyProductId else { continue }
            guard transaction.revocationDate == nil else { continue }
            active = true
            if let exp = transaction.expirationDate {
                latestExpiration = latestExpiration.map { max($0, exp) } ?? exp
            }
        }
        return (active, latestExpiration)
    }
}
