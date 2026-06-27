package com.treelet.treelethub.locale

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Android 端界面语言：冷启动按**本机**系统语言决定默认（仅简体中文 → 中文，否则英语）。
 * 与 iOS / Mac 使用**不同**的存储键，三端语言设置**不会**互相同步。
 */
object HubAndroidUILanguage {
    const val STORAGE_KEY = "treelethub.android.uiLocaleIdentifier"
    const val LOCALE_EN = "en"
    const val LOCALE_ZH_HANS = "zh-Hans"

    private const val PREFS_NAME = "treelethub.prefs"

    fun bootstrapIfNeeded(context: Context) {
        val prefs = prefs(context)
        if (!prefs.contains(STORAGE_KEY)) {
            prefs.edit().putString(STORAGE_KEY, defaultLocaleIdentifierForSystem()).apply()
        }
    }

    fun getLocaleIdentifier(context: Context): String {
        bootstrapIfNeeded(context)
        val stored = prefs(context).getString(STORAGE_KEY, LOCALE_EN) ?: LOCALE_EN
        return if (stored == LOCALE_ZH_HANS) LOCALE_ZH_HANS else LOCALE_EN
    }

    fun setLocaleIdentifier(context: Context, identifier: String) {
        val id = if (identifier == LOCALE_ZH_HANS) LOCALE_ZH_HANS else LOCALE_EN
        prefs(context).edit().putString(STORAGE_KEY, id).apply()
    }

    /** 固定为各自书写：English / 简体中文 */
    fun displayName(context: Context): String =
        if (getLocaleIdentifier(context) == LOCALE_ZH_HANS) {
            "简体中文"
        } else {
            "English"
        }

    fun wrapContext(context: Context): Context {
        val locale = toJavaLocale(getLocaleIdentifier(context))
        val config = Configuration(context.resources.configuration)
        config.setLocale(locale)
        return context.createConfigurationContext(config)
    }

    fun defaultLocaleIdentifierForSystem(): String {
        val tag =
            Locale.getDefault().toLanguageTag().trim().replace('_', '-')
        if (tag.isEmpty()) return LOCALE_EN
        val lower = tag.lowercase(Locale.ROOT)
        if (lower == "zh-hans" || lower.startsWith("zh-hans-")) return LOCALE_ZH_HANS
        if (lower == "zh-cn" || lower.startsWith("zh-cn-")) return LOCALE_ZH_HANS
        val locale = Locale.forLanguageTag(tag)
        if (locale.language == "zh" && locale.script == "Hans") return LOCALE_ZH_HANS
        return LOCALE_EN
    }

    private fun toJavaLocale(identifier: String): Locale =
        when (identifier) {
            LOCALE_ZH_HANS -> Locale.forLanguageTag("zh-Hans")
            else -> Locale.ENGLISH
        }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
