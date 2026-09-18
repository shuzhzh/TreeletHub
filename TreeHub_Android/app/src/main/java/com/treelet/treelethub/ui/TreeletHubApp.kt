@file:OptIn(ExperimentalMaterial3Api::class)

package com.treelet.treelethub.ui

import android.net.Uri
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeDown
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Grid3x3
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.treelet.treelethub.R
import com.treelet.treelethub.billing.HubAndroidBillingManager
import com.treelet.treelethub.hub.HubAndroidClient
import com.treelet.treelethub.hub.HubAndroidUiState
import com.treelet.treelethub.hub.HubClientPhase
import com.treelet.treelethub.hub.HubCodexControlTarget
import com.treelet.treelethub.hub.HubCustomBackgroundStore
import com.treelet.treelethub.hub.HubGestureCommand
import com.treelet.treelethub.hub.HubPageConfig
import com.treelet.treelethub.hub.HubService
import com.treelet.treelethub.hub.HubSlotConfig
import com.treelet.treelethub.hub.normalized
import com.treelet.treelethub.ui.theme.TreeletHubTheme
import kotlin.math.abs
import kotlin.math.hypot
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

@Composable
fun TreeletHubApp(vm: TreeletHubViewModel) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("treelethub.prefs", android.content.Context.MODE_PRIVATE) }
    var bgPresetRaw by remember { mutableStateOf(prefs.getString("treelethub.bg.preset", HubBackgroundPreset.SYSTEM.raw) ?: HubBackgroundPreset.SYSTEM.raw) }
    var useCustomBackground by remember { mutableStateOf(prefs.getBoolean("treelethub.bg.useCustom", false)) }
    val bgStore = remember { HubCustomBackgroundStore(context) }

    val preset = remember(bgPresetRaw) { HubBackgroundPreset.fromRaw(bgPresetRaw) }
    val forceDark =
        if (useCustomBackground) {
            null
        } else if (preset.forcesDarkTheme()) {
            true
        } else {
            null
        }
    val dynamicColor = !useCustomBackground && preset == HubBackgroundPreset.SYSTEM

    val ui by vm.client.state.collectAsStateWithLifecycle()
    val billing = vm.billing

    LaunchedEffect(useCustomBackground, bgStore.bitmap) {
        if (useCustomBackground && bgStore.bitmap == null) {
            useCustomBackground = false
            prefs.edit().putBoolean("treelethub.bg.useCustom", false).apply()
        }
    }

    TreeletHubTheme(darkTheme = forceDark, dynamicColor = dynamicColor) {
        val brush = preset.backgroundBrush()
        val bgModifier =
            Modifier
                .fillMaxSize()
                .then(
                    if (useCustomBackground && bgStore.bitmap != null) {
                        Modifier.background(
                            brush =
                                Brush.verticalGradient(
                                    colors = listOf(Color.Black.copy(alpha = 0.35f), Color.Black.copy(alpha = 0.55f)),
                                ),
                        )
                    } else if (brush != null) {
                        Modifier.background(brush)
                    } else {
                        Modifier.background(MaterialTheme.colorScheme.background)
                    },
                )

        Box(modifier = bgModifier) {
            if (useCustomBackground && bgStore.bitmap != null) {
                Image(
                    bitmap = bgStore.bitmap!!,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            }

            when (ui.phase) {
                HubClientPhase.Paired ->
                    PairedShell(
                        vm = vm,
                        ui = ui,
                        billing = billing,
                        prefs = prefs,
                        bgPresetRaw = bgPresetRaw,
                        onBgPresetChange = { raw ->
                            bgPresetRaw = raw
                            prefs.edit().putString("treelethub.bg.preset", raw).apply()
                        },
                        useCustomBackground = useCustomBackground,
                        onUseCustomBackgroundChange = { v ->
                            useCustomBackground = v
                            prefs.edit().putBoolean("treelethub.bg.useCustom", v).apply()
                        },
                        bgStore = bgStore,
                    )
                else ->
                    ConnectMacScreen(
                        vm = vm,
                        ui = ui,
                    )
            }
        }

        val disconnectMsg = ui.serverDisconnectAlertMessage
        if (disconnectMsg != null) {
            val fallbackDisconnect = stringResource(R.string.disconnect_server_message)
            AlertDialog(
                onDismissRequest = { vm.client.returnToPairingAfterServerDisconnect() },
                title = { Text(stringResource(R.string.alert_disconnect_title)) },
                text = { Text(disconnectMsg.ifBlank { fallbackDisconnect }) },
                confirmButton = {
                    TextButton(onClick = { vm.client.returnToPairingAfterServerDisconnect() }) {
                        Text(stringResource(R.string.common_ok))
                    }
                },
            )
        }
    }
}

@Composable
private fun ConnectMacScreen(
    vm: TreeletHubViewModel,
    ui: HubAndroidUiState,
) {
    Scaffold(
        containerColor = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onSurface,
        topBar = {
            TopAppBar(title = { Text(stringResource(R.string.connect_title)) })
        },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                stringResource(R.string.connect_intro),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(stringResource(R.string.connect_pairing_label), style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = ui.pinInput,
                onValueChange = { vm.client.setPinInput(it) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text(stringResource(R.string.connect_pin_placeholder)) },
            )
            if (ui.didLoadCachedPairing) {
                Text(
                    stringResource(R.string.connect_cached_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Button(
                onClick = { vm.client.connectUsingEnteredPin() },
                enabled = ui.phase != HubClientPhase.Connecting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    stringResource(
                        if (ui.phase == HubClientPhase.Browsing || ui.phase == HubClientPhase.Connecting) {
                            R.string.connect_button_connecting
                        } else {
                            R.string.connect_button_connect
                        },
                    ),
                )
            }
            if (ui.phase == HubClientPhase.Browsing || ui.phase == HubClientPhase.Connecting) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text(
                        stringResource(
                            if (ui.phase == HubClientPhase.Connecting) {
                                R.string.connect_connecting
                            } else {
                                R.string.connect_find_mac
                            },
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = { vm.client.userStopScanning() }) {
                    Text(stringResource(R.string.common_cancel))
                }
            }
            ui.lastError?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            Text(
                stringResource(R.string.connect_wifi_hint),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
            )
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            UserGuideCard()
            HubLanguageMenuRow(
                modifier =
                    Modifier
                        .padding(16.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.65f),
                            RoundedCornerShape(14.dp),
                        )
                        .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun UserGuideCard() {
    Surface(
        tonalElevation = 1.dp,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            GuideBlock(R.string.guide_title_what, R.string.guide_body_what)
            GuideBlock(R.string.guide_title_scenarios, R.string.guide_body_scenarios)
            GuideBlock(R.string.guide_title_connect_android, R.string.guide_body_connect_android)
            GuideBlock(R.string.guide_title_setup_mac, R.string.guide_body_setup_mac)
            GuideBlock(R.string.guide_title_setup_phone, R.string.guide_body_setup_phone)
            GuideBlock(R.string.guide_title_ai_pad_phone, R.string.guide_body_ai_pad_phone)
            GuideBlock(R.string.guide_title_island, R.string.guide_body_island)
            GuideBlock(R.string.guide_title_keyboard_hud, R.string.guide_body_keyboard_hud)
            GuideBlock(R.string.guide_title_pro, R.string.guide_body_pro)
            GuideBlock(R.string.guide_title_gestures_phone, R.string.guide_body_gestures_phone)
            GuideBlock(R.string.guide_title_tabs_swipe, R.string.guide_body_tabs_swipe)
        }
    }
}

@Composable
private fun GuideBlock(
  @androidx.annotation.StringRes titleRes: Int,
  @androidx.annotation.StringRes bodyRes: Int,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(titleRes), style = MaterialTheme.typography.titleSmall)
        Text(
            stringResource(bodyRes),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PairedShell(
    vm: TreeletHubViewModel,
    ui: HubAndroidUiState,
    billing: HubAndroidBillingManager,
    prefs: android.content.SharedPreferences,
    bgPresetRaw: String,
    onBgPresetChange: (String) -> Unit,
    useCustomBackground: Boolean,
    onUseCustomBackgroundChange: (Boolean) -> Unit,
    bgStore: HubCustomBackgroundStore,
) {
    val hasPremium =
        ui.serverReportsSubscriptionActive || billing.isSubscribed
    val sortedPages = ui.pages.sortedBy { it.id }
    val displayPages =
        remember(sortedPages, hasPremium) {
            if (sortedPages.isEmpty()) {
                listOf(HubPageConfig(id = 0, title = "Apps").normalized())
            } else if (hasPremium) {
                sortedPages.take(HubService.maxTabs)
            } else {
                sortedPages.firstOrNull { it.id == 0 }?.let { listOf(it) } ?: listOf(sortedPages.first())
            }
        }

    val tabTags =
        remember(displayPages) {
            displayPages.map { "page-${it.id}" } + "settings"
        }
    val pagerState = rememberPagerState(pageCount = { tabTags.size })
    val scope = rememberCoroutineScope()
    var microTarget by remember { mutableStateOf<HubCodexControlTarget?>(null) }

    LaunchedEffect(displayPages, hasPremium) {
        if (pagerState.currentPage >= tabTags.size) {
            scope.launch { pagerState.scrollToPage(0) }
        }
    }

    val activity = LocalContext.current as androidx.activity.ComponentActivity

    if (microTarget != null) {
        HubCodexMicroScreen(
            client = vm.client,
            lockedTarget = microTarget!!,
            onBack = {
                vm.client.pttCancel()
                microTarget = null
            },
        )
        return
    }

    Scaffold(
        containerColor = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onSurface,
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.62f),
            ) {
                displayPages.forEachIndexed { index, page ->
                    NavigationBarItem(
                        selected = pagerState.currentPage == index,
                        onClick = {
                            microTarget = null
                            scope.launch { pagerState.animateScrollToPage(index) }
                        },
                        icon = { Icon(Icons.Default.Grid3x3, contentDescription = null) },
                        label = { Text(page.title) },
                    )
                }
                NavigationBarItem(
                    selected = pagerState.currentPage == displayPages.size,
                    onClick = {
                        microTarget = null
                        scope.launch { pagerState.animateScrollToPage(displayPages.size) }
                    },
                    icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_settings)) },
                )
            }
        },
    ) { padding ->
        HorizontalPager(
            state = pagerState,
            modifier =
                Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .twoFingerSwipeDown {
                        vm.client.gesture(HubGestureCommand.ShowDesktop)
                    },
            beyondViewportPageCount = 1,
            userScrollEnabled = true,
        ) { pageIndex ->
            if (pageIndex < displayPages.size) {
                val page = displayPages[pageIndex]
                HubAppsPage(
                    vm = vm,
                    page = page,
                    layoutEpoch = ui.layoutApplyEpoch,
                    useCustomBackground = useCustomBackground,
                    onOpenCodexPad = { target -> microTarget = target },
                )
            } else {
                SettingsNavHost(
                    vm = vm,
                    billing = billing,
                    prefs = prefs,
                    bgPresetRaw = bgPresetRaw,
                    onBgPresetChange = onBgPresetChange,
                    useCustomBackground = useCustomBackground,
                    onUseCustomBackgroundChange = onUseCustomBackgroundChange,
                    bgStore = bgStore,
                    activity = activity,
                    serverReportsSubscriptionActive = ui.serverReportsSubscriptionActive,
                )
            }
        }
    }
}

private fun Modifier.twoFingerSwipeDown(onSwipe: () -> Unit): Modifier =
    pointerInput(onSwipe) {
        var lastFireAt = 0L
        awaitEachGesture {
            val first = awaitFirstDown(requireUnconsumed = false)
            val second =
                withTimeoutOrNull(220) {
                    awaitFirstDown(requireUnconsumed = false)
                } ?: return@awaitEachGesture
            var totalX = 0f
            var totalY = 0f
            var tracking = true
            while (tracking) {
                val event = awaitPointerEvent()
                val pressed = event.changes.filter { it.pressed }
                if (pressed.size < 2) {
                    tracking = false
                    break
                }
                event.changes.forEach { change ->
                    if (change.pressed) {
                        val delta = change.positionChange()
                        totalX += delta.x
                        totalY += delta.y
                    }
                }
                if (event.changes.all { it.changedToUp() }) {
                    tracking = false
                }
            }
            val distance = hypot(totalX.toDouble(), totalY.toDouble())
            if (distance < 48) return@awaitEachGesture
            if (totalY <= 36 || totalY <= abs(totalX) * 0.85f) return@awaitEachGesture
            val now = System.currentTimeMillis()
            if (now - lastFireAt < 400) return@awaitEachGesture
            lastFireAt = now
            onSwipe()
            // Keep first/second referenced so the compiler keeps the await.
            first.id
            second.id
        }
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsNavHost(
    vm: TreeletHubViewModel,
    billing: HubAndroidBillingManager,
    prefs: android.content.SharedPreferences,
    bgPresetRaw: String,
    onBgPresetChange: (String) -> Unit,
    useCustomBackground: Boolean,
    onUseCustomBackgroundChange: (Boolean) -> Unit,
    bgStore: HubCustomBackgroundStore,
    activity: androidx.activity.ComponentActivity,
    serverReportsSubscriptionActive: Boolean,
) {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = "root") {
        composable("root") {
            SettingsRootScreen(
                vm = vm,
                billing = billing,
                prefs = prefs,
                bgPresetRaw = bgPresetRaw,
                onBgPresetChange = onBgPresetChange,
                useCustomBackground = useCustomBackground,
                onUseCustomBackgroundChange = onUseCustomBackgroundChange,
                bgStore = bgStore,
                activity = activity,
                serverReportsSubscriptionActive = serverReportsSubscriptionActive,
                onOpenGuide = { nav.navigate("guide") },
            )
        }
        composable("guide") {
            Scaffold(
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.onSurface,
                topBar = {
                    TopAppBar(
                        title = { Text(stringResource(R.string.guide_nav_title)) },
                        navigationIcon = {
                            IconButton(onClick = { nav.popBackStack() }) {
                                Icon(
                                    Icons.AutoMirrored.Filled.ArrowBack,
                                    contentDescription = stringResource(R.string.common_back),
                                )
                            }
                        },
                    )
                },
            ) { padding ->
                Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(20.dp)) {
                    UserGuideCard()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsRootScreen(
    vm: TreeletHubViewModel,
    billing: HubAndroidBillingManager,
    prefs: android.content.SharedPreferences,
    bgPresetRaw: String,
    onBgPresetChange: (String) -> Unit,
    useCustomBackground: Boolean,
    onUseCustomBackgroundChange: (Boolean) -> Unit,
    bgStore: HubCustomBackgroundStore,
    activity: androidx.activity.ComponentActivity,
    serverReportsSubscriptionActive: Boolean,
    onOpenGuide: () -> Unit,
) {
    val context = LocalContext.current
    var deviceName by remember {
        mutableStateOf(prefs.getString(HubAndroidClient.customDeviceNameKey, "") ?: "")
    }
    val pick =
        rememberLauncherForActivityResult(
            contract = ActivityResultContracts.PickVisualMedia(),
        ) { uri: Uri? ->
            if (uri == null) return@rememberLauncherForActivityResult
            context.contentResolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                bgStore.saveJpeg(bytes)
                onUseCustomBackgroundChange(true)
            }
        }

    Scaffold(
        containerColor = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onSurface,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_title)) }) },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(stringResource(R.string.settings_section_device), style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(
                value = deviceName,
                onValueChange = { v ->
                    val t = v.trim().take(40)
                    deviceName = t
                    prefs.edit().putString(HubAndroidClient.customDeviceNameKey, t).apply()
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.settings_device_name_placeholder)) },
                singleLine = true,
            )
            Text(
                stringResource(R.string.settings_device_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Button(onClick = onOpenGuide, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Book, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.settings_guide_link))
            }

            Text(stringResource(R.string.settings_section_subscription), style = MaterialTheme.typography.titleSmall)
            when {
                billing.isSubscribed ->
                    Text(
                        stringResource(R.string.settings_subscribed_local),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                serverReportsSubscriptionActive ->
                    Text(
                        stringResource(R.string.settings_subscribed_mac),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                else -> {
                    Text(
                        stringResource(R.string.settings_subscription_paywall),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(
                            onClick = { billing.restorePurchases() },
                            enabled = !billing.isLoading,
                        ) {
                            Text(stringResource(R.string.settings_restore))
                        }
                        TextButton(
                            onClick = { billing.launchPurchaseFlow(activity) },
                            enabled = billing.yearlyProductDetails != null && !billing.isLoading,
                        ) {
                            Text(stringResource(R.string.settings_subscribe))
                        }
                    }
                }
            }
            billing.lastError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }

            Text(stringResource(R.string.settings_section_background), style = MaterialTheme.typography.titleSmall)
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .height(220.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(HubBackgroundPreset.entries.toList()) { preset ->
                    val selected = !useCustomBackground && preset.raw == bgPresetRaw
                    Box(
                        modifier =
                            Modifier
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .border(
                                    width = if (selected) 2.dp else 1.dp,
                                    color =
                                        if (selected) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
                                        },
                                    shape = RoundedCornerShape(12.dp),
                                )
                                .clickable {
                                    onUseCustomBackgroundChange(false)
                                    onBgPresetChange(preset.raw)
                                },
                    ) {
                        if (preset == HubBackgroundPreset.SYSTEM) {
                            Box(
                                Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(preset.displayName(), fontSize = 12.sp, textAlign = TextAlign.Center)
                            }
                        } else {
                            val b = preset.backgroundBrush()
                            if (b != null) {
                                Box(Modifier.fillMaxSize().background(b))
                            }
                        }
                        if (selected) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp),
                            )
                        }
                    }
                }
                item {
                    val thumb = bgStore.bitmap
                    Box(
                        modifier =
                            Modifier
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                                .clickable {
                                    if (thumb != null) {
                                        onUseCustomBackgroundChange(true)
                                    }
                                },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (thumb != null) {
                            Image(
                                bitmap = thumb,
                                contentDescription = null,
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Crop,
                            )
                            if (useCustomBackground) {
                                Icon(
                                    Icons.Default.CheckCircle,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp),
                                )
                            }
                        } else {
                            Icon(Icons.Default.Add, contentDescription = stringResource(R.string.a11y_add_custom_bg))
                        }
                    }
                }
                item {
                    Box(
                        modifier =
                            Modifier
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                                .clickable {
                                    pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.a11y_pick_photo))
                    }
                }
            }
            Text(
                stringResource(R.string.settings_background_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (bgStore.bitmap != null) {
                TextButton(onClick = {
                    bgStore.deleteCustomFile()
                    onUseCustomBackgroundChange(false)
                }) {
                    Text(
                        stringResource(R.string.settings_delete_photo_bg),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            Button(
                onClick = { vm.client.disconnect() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_disconnect))
            }
            Text(
                stringResource(R.string.settings_disconnect_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HubLanguageMenuRow()
        }
    }
}

@Composable
private fun HubGridSlot(
    vm: TreeletHubViewModel,
    pageId: Int,
    slot: HubSlotConfig,
    layoutEpoch: Long,
    useCustomBackground: Boolean,
    slotBounds: MutableMap<Int, Rect>,
    layoutCoords: Map<Int, LayoutCoordinates?>,
    onSlotPositioned: (Int, LayoutCoordinates) -> Unit,
    onOpenCodexPad: (HubCodexControlTarget) -> Unit,
    modifier: Modifier = Modifier,
) {
    val layoutCoordsLatest by rememberUpdatedState(layoutCoords)
    val dragFromSlot = remember(slot.id, pageId, layoutEpoch) { mutableIntStateOf(-1) }
    var startRoot by remember(slot.id, pageId, layoutEpoch) { mutableStateOf(Offset.Zero) }
    var totalDrag by remember(slot.id, pageId, layoutEpoch) { mutableStateOf(Offset.Zero) }

    val isInteractiveShortcut =
        slot.kind == "shortcut" &&
            (
                slot.shortcutKind == "volume" ||
                    slot.shortcutKind == "brightness" ||
                    slot.shortcutKind == "mediaTransport"
            )

    val canDrag = !slot.isEmpty && slot.kind == "app"
    val view = LocalView.current
    var tapScale by remember(slot.id, pageId, layoutEpoch) { mutableFloatStateOf(1f) }
    val animScale by animateFloatAsState(tapScale, animationSpec = spring(), label = "tap")

    val cellModifier =
        Modifier
            .onGloballyPositioned { coords -> onSlotPositioned(slot.id, coords) }
            .then(
                if (canDrag) {
                    val pageIdUpdated by rememberUpdatedState(pageId)
                    val coordsProvider = { layoutCoordsLatest[slot.id] }
                    Modifier.pointerInput(slot.id, layoutEpoch, canDrag) {
                        detectDragGesturesAfterLongPress(
                            onDragStart = { local ->
                                val c = coordsProvider() ?: return@detectDragGesturesAfterLongPress
                                dragFromSlot.intValue = slot.id
                                startRoot = c.localToRoot(local)
                                totalDrag = Offset.Zero
                            },
                            onDrag = { _, delta ->
                                totalDrag += delta
                            },
                            onDragEnd = {
                                val from = dragFromSlot.intValue
                                dragFromSlot.intValue = -1
                                if (from !in 0..8) return@detectDragGesturesAfterLongPress
                                val end = startRoot + totalDrag
                                val to =
                                    slotBounds.entries.firstOrNull { (id, r) ->
                                        id != from && r.contains(end)
                                    }?.key
                                if (to != null) {
                                    vm.client.reorder(pageIdUpdated, from, to)
                                }
                            },
                            onDragCancel = { dragFromSlot.intValue = -1 },
                        )
                    }
                } else {
                    Modifier
                },
            )

    Card(
        modifier =
            modifier
                .fillMaxSize()
                .then(cellModifier),
        colors =
            CardDefaults.cardColors(
                containerColor =
                    if (useCustomBackground) {
                        Color.Transparent
                    } else {
                        MaterialTheme.colorScheme.surface.copy(alpha = 0.52f)
                    },
            ),
        shape = RoundedCornerShape(18.dp),
    ) {
        Box(Modifier.fillMaxSize()) {
            if (isInteractiveShortcut) {
                ShortcutSlot(
                    slot = slot,
                    onControl = { cmd, v -> vm.client.control(pageId, slot.id, cmd, v) },
                )
            } else {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(8.dp)
                        .clickable(enabled = !slot.isEmpty) {
                            if (slot.kind == "shortcut") {
                                if (slot.shortcutKind == "volume") {
                                    vm.client.control(pageId, slot.id, "toggleMute", null)
                                } else {
                                    vm.client.tap(pageId, slot.id)
                                }
                            } else {
                                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                tapScale = 1.12f
                                vm.client.tap(pageId, slot.id)
                                HubCodexControlTarget
                                    .resolve(slot.bundleIdentifier, slot.displayName)
                                    ?.takeIf { it in HubCodexControlTarget.padSupportedTargets }
                                    ?.let(onOpenCodexPad)
                                tapScale = 1f
                            }
                        },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    if (slot.kind == "shortcut") {
                        ShortcutIcon(slot = slot)
                        if (!useCustomBackground) {
                            Text(
                                slot.displayName ?: shortcutTitle(slot.shortcutKind),
                                style = MaterialTheme.typography.labelSmall,
                                textAlign = TextAlign.Center,
                                maxLines = 2,
                            )
                        }
                    } else {
                        BoxWithConstraints(
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            val side =
                                (minOf(maxWidth, maxHeight) * 0.74f).coerceIn(36.dp, 172.dp)
                            SlotAppIcon(slot = slot, modifier = Modifier.scale(animScale), iconSide = side)
                        }
                        if (!useCustomBackground) {
                            Text(
                                slot.displayName
                                    ?: if (slot.isEmpty) {
                                        stringResource(R.string.slot_empty)
                                    } else {
                                        stringResource(R.string.slot_app)
                                    },
                                style = MaterialTheme.typography.labelSmall,
                                textAlign = TextAlign.Center,
                                maxLines = 2,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HubAppsPage(
    vm: TreeletHubViewModel,
    page: HubPageConfig,
    layoutEpoch: Long,
    useCustomBackground: Boolean,
    onOpenCodexPad: (HubCodexControlTarget) -> Unit,
) {
    val slots = page.slots.orEmpty().sortedBy { it.id }
    if (slots.size != 9) return

    val slotBounds = remember { mutableStateMapOf<Int, Rect>() }
    var layoutCoords by remember { mutableStateOf<Map<Int, LayoutCoordinates?>>(emptyMap()) }

    val onSlotPositioned: (Int, LayoutCoordinates) -> Unit = { id, coords ->
        slotBounds[id] = coords.boundsInRoot()
        layoutCoords = layoutCoords.toMutableMap().also { it[id] = coords }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val spacing = (minOf(maxWidth, maxHeight) * 0.03f).coerceIn(8.dp, 22.dp)
        val horizontalPadding = (maxWidth * 0.05f).coerceIn(12.dp, 28.dp)
        val verticalPadding = (maxHeight * 0.03f).coerceIn(8.dp, 24.dp)

        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = horizontalPadding, vertical = verticalPadding),
            verticalArrangement = Arrangement.spacedBy(spacing),
        ) {
            for (row in 0..2) {
                Row(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(spacing),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    for (col in 0..2) {
                        val slot = slots[row * 3 + col]
                        key("${page.id}-${slot.id}-$layoutEpoch-$row-$col") {
                            HubGridSlot(
                                vm = vm,
                                pageId = page.id,
                                slot = slot,
                                layoutEpoch = layoutEpoch,
                                useCustomBackground = useCustomBackground,
                                slotBounds = slotBounds,
                                layoutCoords = layoutCoords,
                                onSlotPositioned = onSlotPositioned,
                                onOpenCodexPad = onOpenCodexPad,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SlotAppIcon(
    slot: HubSlotConfig,
    modifier: Modifier = Modifier,
    iconSide: Dp = 52.dp,
) {
    val bytes = remember(slot.iconPNG, slot.id) { slot.iconPngBytes() }
    val bmp: ImageBitmap? =
        remember(bytes) {
            bytes?.let {
                if (it.size < 32) return@let null
                val b = android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)
                b?.asImageBitmap()
            }
        }
    Box(
        modifier
            .size(iconSide),
        contentAlignment = Alignment.Center,
    ) {
        when {
            slot.isEmpty -> Icon(Icons.Default.Apps, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
            bmp != null -> Image(bmp, null, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
            else -> Icon(Icons.Default.Apps, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
        }
    }
}

@Composable
private fun ShortcutIcon(slot: HubSlotConfig) {
    val kind = slot.shortcutKind.orEmpty()
    when (kind) {
        "openURL" -> {
            val ctx = LocalContext.current
            val host =
                remember(slot.shortcutPayload) {
                    runCatching { android.net.Uri.parse(slot.shortcutPayload)?.host }.getOrNull()
                }
            val url = remember(host) { host?.takeIf { it.isNotBlank() }?.let { h -> "https://$h/favicon.ico" } }
            val iconBytes = remember(slot.iconPNG) { slot.iconPngBytes() }
            val bmp =
                remember(iconBytes) {
                    iconBytes?.let {
                        android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap()
                    }
                }
            if (bmp != null) {
                Image(bmp, null, Modifier.size(28.dp))
            } else if (url != null) {
                AsyncImage(
                    model =
                        ImageRequest.Builder(ctx)
                            .data(url)
                            .crossfade(true)
                            .build(),
                    contentDescription = null,
                    modifier = Modifier.size(28.dp),
                )
            } else {
                Icon(Icons.Default.Link, contentDescription = null)
            }
        }
        "volume" -> Icon(Icons.Default.VolumeUp, contentDescription = null)
        "brightness" -> Icon(Icons.Default.WbSunny, contentDescription = null)
        "mediaTransport" -> Icon(Icons.Default.Speed, contentDescription = null)
        "screenshotFull", "screenshotSelection" -> Icon(Icons.Default.PhotoCamera, contentDescription = null)
        "selectAll" -> Icon(Icons.Default.SelectAll, contentDescription = null)
        "copy" -> Icon(Icons.Default.ContentCopy, contentDescription = null)
        "paste" -> Icon(Icons.Default.ContentPaste, contentDescription = null)
        else -> Icon(Icons.Default.Apps, contentDescription = null)
    }
}

@Composable
private fun shortcutTitle(kind: String?): String =
    when (kind) {
        "volume" -> stringResource(R.string.shortcut_volume)
        "brightness" -> stringResource(R.string.shortcut_brightness)
        "mediaTransport" -> stringResource(R.string.shortcut_media)
        "screenshotFull" -> stringResource(R.string.shortcut_screenshot_full)
        "screenshotSelection" -> stringResource(R.string.shortcut_screenshot_region)
        "selectAll" -> stringResource(R.string.shortcut_select_all)
        "copy" -> stringResource(R.string.shortcut_copy)
        "paste" -> stringResource(R.string.shortcut_paste)
        "openURL" -> stringResource(R.string.shortcut_open_url)
        else -> stringResource(R.string.shortcut_other)
    }

@Composable
private fun ShortcutSlot(
    slot: HubSlotConfig,
    onControl: (String?, Double?) -> Unit,
) {
    val kind = slot.shortcutKind.orEmpty()
    Column(
        Modifier
            .fillMaxSize()
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
    ) {
        Text(
            slot.displayName ?: shortcutTitle(kind),
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
        when (kind) {
            "volume", "brightness" -> {
                var bar by remember { mutableFloatStateOf(0.5f) }
                val tint =
                    if (kind == "volume") {
                        MaterialTheme.colorScheme.primary
                    } else {
                        Color(0xFFFFC107)
                    }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    VerticalControlBar(
                        value = bar,
                        tint = tint,
                        onChange = { v ->
                            bar = v
                            onControl(null, v.toDouble())
                        },
                    )
                    if (kind == "volume") {
                        IconButton(onClick = { onControl("toggleMute", null) }) {
                            Icon(Icons.AutoMirrored.Filled.VolumeDown, contentDescription = "静音切换")
                        }
                    }
                }
            }
            "mediaTransport" -> {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = { onControl("previous", null) }) {
                        Text("⏮", fontSize = 20.sp)
                    }
                    IconButton(onClick = { onControl("next", null) }) {
                        Text("⏭", fontSize = 20.sp)
                    }
                }
                IconButton(onClick = { onControl("playPause", null) }) {
                    Text("⏯", fontSize = 22.sp)
                }
            }
            else -> ShortcutIcon(slot = slot)
        }
    }
}

@Composable
private fun VerticalControlBar(
    value: Float,
    tint: Color,
    onChange: (Float) -> Unit,
) {
    BoxWithConstraints(
        Modifier
            .widthIn(max = 44.dp)
            .fillMaxHeight(0.85f),
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)),
        )
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth(0.36f)
                .fillMaxHeight(value.coerceIn(0.05f, 1f))
                .clip(RoundedCornerShape(8.dp))
                .background(tint.copy(alpha = 0.85f)),
        )
        Box(
                Modifier
                    .fillMaxSize()
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        val y = change.position.y
                        val nh = size.height.toFloat().coerceAtLeast(1f)
                        val normalized = 1f - (y / nh).coerceIn(0f, 1f)
                        onChange(normalized)
                    }
                },
        )
    }
}
