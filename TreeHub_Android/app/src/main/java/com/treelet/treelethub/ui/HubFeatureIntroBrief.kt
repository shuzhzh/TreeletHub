package com.treelet.treelethub.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.treelet.treelethub.R

enum class HubFeatureIntroStyle {
    Embedded,
    Sheet,
}

/** 对齐 iOS HubFeatureIntroBrief：连接页嵌入 / 设置全文。 */
@Composable
fun HubFeatureIntroBrief(
    style: HubFeatureIntroStyle = HubFeatureIntroStyle.Embedded,
    modifier: Modifier = Modifier,
) {
    val spacing = if (style == HubFeatureIntroStyle.Sheet) 18.dp else 14.dp
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(spacing),
    ) {
        if (style == HubFeatureIntroStyle.Sheet) {
            Text(
                stringResource(R.string.intro_title),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                stringResource(R.string.intro_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    stringResource(R.string.intro_title),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Text(
                stringResource(R.string.intro_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(if (style == HubFeatureIntroStyle.Sheet) 14.dp else 12.dp)) {
            IntroRow(
                icon = Icons.Default.Computer,
                title = stringResource(R.string.intro_step1_title),
                body = stringResource(R.string.intro_step1_body),
            )
            IntroRow(
                icon = Icons.Default.PhoneAndroid,
                title = stringResource(R.string.intro_step2_title),
                body = stringResource(R.string.intro_step2_body),
            )
            IntroRow(
                icon = Icons.Default.AddCircle,
                title = stringResource(R.string.intro_step3_title),
                body = stringResource(R.string.intro_step3_body),
            )
            IntroRow(
                icon = Icons.Default.Widgets,
                title = stringResource(R.string.intro_step4_title),
                body = stringResource(R.string.intro_step4_body),
            )
        }
    }
}

@Composable
private fun IntroRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    body: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Surface(
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
            shape = RoundedCornerShape(8.dp),
            modifier = Modifier.size(28.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(4.dp),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                body,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
