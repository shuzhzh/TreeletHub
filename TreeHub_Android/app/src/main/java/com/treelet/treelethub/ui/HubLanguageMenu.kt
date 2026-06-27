package com.treelet.treelethub.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.treelet.treelethub.R
import com.treelet.treelethub.locale.HubAndroidUILanguage

@Composable
fun HubLanguageMenuRow(
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val activity = context as? ComponentActivity
    var expanded by remember { mutableStateOf(false) }
    val current = HubAndroidUILanguage.displayName(context)
    val a11y = stringResource(R.string.lang_menu_a11y)

    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .clickable { expanded = true }
                .semantics { contentDescription = a11y }
                .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(current, style = MaterialTheme.typography.bodyLarge)
        Icon(
            Icons.Default.ArrowDropDown,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }

    DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
    ) {
        DropdownMenuItem(
            text = { Text("English") },
            onClick = {
                expanded = false
                if (HubAndroidUILanguage.getLocaleIdentifier(context) != HubAndroidUILanguage.LOCALE_EN) {
                    HubAndroidUILanguage.setLocaleIdentifier(context, HubAndroidUILanguage.LOCALE_EN)
                    activity?.recreate()
                }
            },
        )
        DropdownMenuItem(
            text = { Text("简体中文") },
            onClick = {
                expanded = false
                if (HubAndroidUILanguage.getLocaleIdentifier(context) != HubAndroidUILanguage.LOCALE_ZH_HANS) {
                    HubAndroidUILanguage.setLocaleIdentifier(context, HubAndroidUILanguage.LOCALE_ZH_HANS)
                    activity?.recreate()
                }
            },
        )
    }
}
