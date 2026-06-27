package com.treelet.treelethub.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import com.treelet.treelethub.R

enum class HubBackgroundPreset(
    val raw: String,
    @StringRes val labelRes: Int,
) {
    SYSTEM("system", R.string.bg_preset_system),
    PORCELAIN_LIGHT("porcelainLight", R.string.bg_preset_porcelain_light),
    DAWN_BLUSH("dawnBlush", R.string.bg_preset_dawn_blush),
    SAGE_MIST("sageMist", R.string.bg_preset_sage_mist),
    DEEP_AZURE("deepAzure", R.string.bg_preset_deep_azure),
    ROYAL_PLUM("royalPlum", R.string.bg_preset_royal_plum),
    CHARCOAL_SILK("charcoalSilk", R.string.bg_preset_charcoal_silk),
    ;

    @Composable
    fun displayName(): String = stringResource(labelRes)

    /** 与 iOS 一致：深色渐变预设强制深色界面 */
    fun forcesDarkTheme(): Boolean =
        when (this) {
            DEEP_AZURE, ROYAL_PLUM, CHARCOAL_SILK -> true
            else -> false
        }

    fun backgroundBrush(): Brush? =
        when (this) {
            SYSTEM -> null
            PORCELAIN_LIGHT ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFFF5F7FC),
                            Color(0xFFE1E8F5),
                            Color(0xFFEBF0FA),
                        ),
                )
            DAWN_BLUSH ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFFFDF0EB),
                            Color(0xFFF5E0E6),
                            Color(0xFFF0D6E0),
                        ),
                )
            SAGE_MIST ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFFEDF5EE),
                            Color(0xFFD6EBE0),
                            Color(0xFFE0F0E6),
                        ),
                )
            DEEP_AZURE ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFF0A1430),
                            Color(0xFF1A2E61),
                            Color(0xFF0F2452),
                        ),
                )
            ROYAL_PLUM ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFF1E1038),
                            Color(0xFF6B3DAA),
                            Color(0xFF22123C),
                        ),
                )
            CHARCOAL_SILK ->
                Brush.verticalGradient(
                    colors =
                        listOf(
                            Color(0xFF1C1C21),
                            Color(0xFF2E2E38),
                            Color(0xFF1E1E26),
                        ),
                )
        }

    companion object {
        fun fromRaw(raw: String?): HubBackgroundPreset =
            entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}
