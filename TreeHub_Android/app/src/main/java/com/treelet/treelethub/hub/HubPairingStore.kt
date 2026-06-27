package com.treelet.treelethub.hub

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class HubPairingCache(
    val pin: String,
    val bonjourServiceName: String? = null,
)

object HubPairingStore {
    private const val PREFS = "treelethub.prefs"
    private const val KEY_PAIRING = "treelethub.pairing.cache.v1"

    private val json = Json { ignoreUnknownKeys = true }

    fun load(context: Context): HubPairingCache? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PAIRING, null)
            ?: return null
        return try {
            json.decodeFromString(HubPairingCache.serializer(), raw)
        } catch (_: Exception) {
            null
        }
    }

    fun save(context: Context, cache: HubPairingCache) {
        val s = json.encodeToString(HubPairingCache.serializer(), cache)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_PAIRING, s).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_PAIRING).apply()
    }
}
