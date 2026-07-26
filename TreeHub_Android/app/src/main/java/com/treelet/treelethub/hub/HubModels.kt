package com.treelet.treelethub.hub

import android.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object HubService {
    const val bonjourType = "_treelethub._tcp."
    const val maxTabs = 5
}

object HubWireOps {
    const val pair = "pair"
    const val pairResult = "pairResult"
    const val layout = "layout"
    const val tap = "tap"
    const val error = "error"
    const val reorder = "reorder"
    const val disconnect = "disconnect"
    const val control = "control"
    const val requestLayout = "requestLayout"
    const val gesture = "gesture"
    const val codexMicro = "codexMicro"
    const val codexMicroState = "codexMicroState"
}

@Serializable
data class HubWireEnvelope(
    val op: String,
    val pin: String? = null,
    val deviceName: String? = null,
    val deviceId: String? = null,
    val ok: Boolean? = null,
    val slots: List<HubSlotConfig>? = null,
    val pages: List<HubPageConfig>? = null,
    val page: Int? = null,
    val slot: Int? = null,
    val message: String? = null,
    val from: Int? = null,
    val to: Int? = null,
    val command: String? = null,
    val value: Double? = null,
    val subscriptionActive: Boolean? = null,
)

@Serializable
data class HubSlotConfig(
    val id: Int,
    val kind: String = "app",
    val bundleIdentifier: String? = null,
    val displayName: String? = null,
    val shortcutKind: String? = null,
    val shortcutPayload: String? = null,
    /** Swift `Data` JSON encoding: Base64 string */
    val iconPNG: String? = null,
) {
    val isEmpty: Boolean
        get() =
            when (kind) {
                "shortcut" -> shortcutKind.isNullOrEmpty()
                else -> bundleIdentifier.isNullOrBlank()
            }

    fun iconPngBytes(): ByteArray? {
        val raw = iconPNG ?: return null
        if (raw.isEmpty()) return null
        return try {
            Base64.decode(raw, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

@Serializable
data class HubPageConfig(
    val id: Int,
    val title: String,
    val slots: List<HubSlotConfig>? = null,
)

object HubWireCodec {
    val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = false
        }

    fun encodeLine(env: HubWireEnvelope): String =
        json.encodeToString(HubWireEnvelope.serializer(), env) + "\n"

    fun decodeLine(line: String): HubWireEnvelope =
        json.decodeFromString(HubWireEnvelope.serializer(), line.trim())
}

fun HubPageConfig.normalized(): HubPageConfig {
    val baseSlots =
        if (slots != null && slots.size == 9) {
            slots.mapIndexed { index, s ->
                s.copy(id = index)
            }
        } else {
            (0..8).map { HubSlotConfig(id = it) }
        }
    return HubPageConfig(id = id, title = title, slots = baseSlots)
}

fun List<HubPageConfig>.normalizedPages(): List<HubPageConfig> =
    sortedBy { it.id }.map { page ->
        val slots =
            page.slots.orEmpty().sortedBy { it.id }.map { slot ->
                val bytes = slot.iconPngBytes()
                if (bytes != null && bytes.isEmpty()) {
                    slot.copy(iconPNG = null)
                } else {
                    slot
                }
            }
        HubPageConfig(id = page.id, title = page.title, slots = slots).normalized()
    }
