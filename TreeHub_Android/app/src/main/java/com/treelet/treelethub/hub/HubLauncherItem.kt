package com.treelet.treelethub.hub

/** 跨页快捷启动条目（page + slot 唯一）。 */
data class HubLauncherItem(
    val pageId: Int,
    val slot: HubSlotConfig,
) {
    val id: String get() = "$pageId-${slot.id}"

    val isAddAffordance: Boolean get() = pageId < 0

    val needsInlineControl: Boolean
        get() {
            if (isAddAffordance) return false
            if (slot.kind != "shortcut") return false
            val kind = slot.shortcutKind ?: return false
            return kind == "volume" || kind == "brightness" || kind == "mediaTransport"
        }

    companion object {
        fun addAffordance(): HubLauncherItem =
            HubLauncherItem(pageId = -1, slot = HubSlotConfig(id = -1))
    }
}

object HubLauncherItems {
    /** 将多页非空槽位收成一条启动列表（保持 page 顺序）。 */
    fun flattened(
        pages: List<HubPageConfig>,
        includeEmpty: Boolean = false,
    ): List<HubLauncherItem> =
        pages.flatMap { page ->
            page.slots
                .orEmpty()
                .filter { includeEmpty || !it.isEmpty }
                .map { HubLauncherItem(pageId = page.id, slot = it) }
        }
}
