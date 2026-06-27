package com.treelet.treelethub.billing

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams

/**
 * 与 iOS `HubIOSSubscriptionManager` 对应：用于解锁多页 Tab（与 Mac `subscriptionActive` 二选一即可）。
 * 需在 Google Play Console 配置订阅商品（与 iOS 商品 ID 不同）。
 */
class HubAndroidBillingManager(
    private val application: Application,
) : PurchasesUpdatedListener {
    companion object {
        /** Play 商品 ID（上架时请与控制台一致） */
        const val yearlyProductId = "com.treelet.treelethub.android.pro.yearly"
        private const val cachedStatusKey = "treelethub.sub.android.cached.active.v1"
    }

    private val main = Handler(Looper.getMainLooper())

    var yearlyProductDetails: ProductDetails? by mutableStateOf(null)
        private set
    var isSubscribed: Boolean by mutableStateOf(false)
        private set
    var isLoading: Boolean by mutableStateOf(false)
        private set
    var lastError: String? by mutableStateOf(null)
        private set

    private val prefs = application.getSharedPreferences("treelethub.prefs", Application.MODE_PRIVATE)

    private val billingClient: BillingClient =
        BillingClient.newBuilder(application)
            .setListener(this)
            .enablePendingPurchases()
            .build()

    init {
        restoreCache()
        startConnectionAndQuery()
    }

    private fun restoreCache() {
        isSubscribed = prefs.getBoolean(cachedStatusKey, false)
    }

    private fun persistCache() {
        prefs.edit().putBoolean(cachedStatusKey, isSubscribed).apply()
    }

    private fun startConnectionAndQuery() {
        billingClient.startConnection(
            object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                        lastError = result.debugMessage
                        return
                    }
                    refreshFromStore()
                }

                override fun onBillingServiceDisconnected() {}
            },
        )
    }

    fun refreshFromStore() {
        isLoading = true
        lastError = null
        val params =
            QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(yearlyProductId)
                            .setProductType(BillingClient.ProductType.SUBS)
                            .build(),
                    ),
                )
                .build()
        billingClient.queryProductDetailsAsync(params) { billingResult, list ->
            main.post {
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    lastError = billingResult.debugMessage
                    isLoading = false
                    return@post
                }
                yearlyProductDetails = list.firstOrNull { it.productId == yearlyProductId }
                queryEntitlements { isLoading = false }
            }
        }
    }

    private fun queryEntitlements(done: (() -> Unit)? = null) {
        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build(),
        ) { billingResult, purchases ->
            main.post {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    val active =
                        purchases.any { purchase ->
                            purchase.products.contains(yearlyProductId) &&
                                purchase.purchaseState == Purchase.PurchaseState.PURCHASED
                        }
                    isSubscribed = active
                    persistCache()
                }
                done?.invoke()
            }
        }
    }

    fun launchPurchaseFlow(activity: androidx.activity.ComponentActivity) {
        val pd = yearlyProductDetails ?: return
        val offerToken =
            pd.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
        val productParams =
            BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(pd)
                .setOfferToken(offerToken)
                .build()
        val flowParams =
            BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(productParams))
                .build()
        billingClient.launchBillingFlow(activity, flowParams)
    }

    fun restorePurchases() {
        isLoading = true
        lastError = null
        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build(),
        ) { billingResult, purchases ->
            main.post {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    val active =
                        purchases.any { purchase ->
                            purchase.products.contains(yearlyProductId) &&
                                purchase.purchaseState == Purchase.PurchaseState.PURCHASED
                        }
                    isSubscribed = active
                    persistCache()
                } else {
                    lastError = billingResult.debugMessage
                }
                isLoading = false
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (p in purchases) {
                if (p.products.contains(yearlyProductId) && p.purchaseState == Purchase.PurchaseState.PURCHASED) {
                    if (!p.isAcknowledged) {
                        val acknowledgeParams =
                            AcknowledgePurchaseParams.newBuilder()
                                .setPurchaseToken(p.purchaseToken)
                                .build()
                        billingClient.acknowledgePurchase(acknowledgeParams) { }
                    }
                }
            }
            queryEntitlements()
        } else if (result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            lastError = result.debugMessage
        }
    }

    fun destroy() {
        billingClient.endConnection()
    }
}
