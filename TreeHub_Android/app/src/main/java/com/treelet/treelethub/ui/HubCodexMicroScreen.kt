@file:OptIn(ExperimentalMaterial3Api::class)

package com.treelet.treelethub.ui

import android.Manifest
import android.content.pm.PackageManager
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.treelet.treelethub.R
import com.treelet.treelethub.hub.HubAndroidClient
import com.treelet.treelethub.hub.HubClientPhase
import com.treelet.treelethub.hub.HubCodexAgentSource
import com.treelet.treelethub.hub.HubCodexAgentStatus
import com.treelet.treelethub.hub.HubCodexControlTarget
import com.treelet.treelethub.hub.HubCodexDialMode
import com.treelet.treelethub.hub.HubCodexJoystickDirection
import com.treelet.treelethub.hub.HubCodexMicroAction
import com.treelet.treelethub.hub.HubCodexMicroMapping
import com.treelet.treelethub.hub.HubCodexRecordingState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.roundToInt

@Composable
fun HubCodexMicroScreen(
    client: HubAndroidClient,
    lockedTarget: HubCodexControlTarget,
    onBack: () -> Unit,
) {
    val ui by client.state.collectAsStateWithLifecycle()
    val state = ui.codexMicroState
    var showSettings by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val view = LocalView.current
    var pendingPttStart by remember { mutableStateOf(false) }

    val micLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted && pendingPttStart) {
                pendingPttStart = false
                client.pttStart()
            } else if (!granted) {
                pendingPttStart = false
                client.codexDismissControlHint()
            }
        }

    fun ensureMicThen(start: () -> Unit) {
        val granted =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        if (granted) {
            start()
        } else {
            pendingPttStart = true
            micLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    LaunchedEffect(lockedTarget) {
        client.codexSetTarget(lockedTarget)
        client.requestCodexMicroState()
    }

    DisposableEffect(Unit) {
        onDispose { client.pttCancel() }
    }

    if (showSettings) {
        HubCodexMicroSettingsScreen(
            client = client,
            lockedTarget = lockedTarget,
            onDismiss = { showSettings = false },
        )
        return
    }

    val chassis =
        Brush.linearGradient(
            listOf(Color(0xFF2A2C30), Color(0xFF141618)),
        )

    Scaffold(
        containerColor = Color(0xFF0E0F11),
        contentColor = Color.White,
        topBar = {
            TopAppBar(
                title = { Text(lockedTarget.displayNameEN) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.common_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { showSettings = true }) {
                        Icon(
                            Icons.Default.Tune,
                            contentDescription = stringResource(R.string.codex_settings),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ConnectionStatusCard(
                clientPhase = ui.phase,
                lockedTarget = lockedTarget,
                state = state,
                onFixPermission = { client.codexOpenAccessibilitySettings() },
                onEnableRetry = { action -> client.codexEnableTextAutomationAndRetry(action) },
                onDismissHint = { client.codexDismissControlHint() },
                chassis = chassis,
            )

            HeaderRow(
                lockedTarget = lockedTarget,
                effectiveRecording =
                    if (ui.localRecordingPhase != HubCodexRecordingState.Idle) {
                        ui.localRecordingPhase
                    } else {
                        state.recording
                    },
            )

            if (ui.localRecordingPhase == HubCodexRecordingState.Recording ||
                ui.localRecordingPhase == HubCodexRecordingState.Processing
            ) {
                LiveTranscriptCard(
                    phase = ui.localRecordingPhase,
                    partial = ui.dictationPartial,
                )
            }

            if (lockedTarget.showsAgentKeys) {
                AgentRow(
                    agents = state.agents,
                    brightness = state.mapping.brightness,
                    dialCancelArmed = state.dialCancelArmed,
                    chassis = chassis,
                    onTap = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        client.codexAgentTap(it)
                    },
                )
            } else {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(chassis)
                        .padding(14.dp),
                ) {
                    Text(
                        stringResource(R.string.codex_cursor_pad_title),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        stringResource(R.string.codex_cursor_pad_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.65f),
                    )
                }
            }

            ControlsRow(
                reasoningLevel = state.reasoningLevel,
                dialMode = state.mapping.dialMode,
                dialCancelArmed = state.dialCancelArmed,
                chassis = chassis,
                onDialTurn = { client.codexDialTurn(it) },
                onDialPress = { client.codexDialPress() },
                onDialLongPress = { client.codexDialLongPress() },
                onDialCancel = { client.codexDialCancel() },
                onJoystick = { client.codexJoystick(it) },
            )

            CommandGrid(
                keys = normalizedCommandKeys(state, lockedTarget),
                isRecording = ui.localRecordingPhase == HubCodexRecordingState.Recording,
                chassis = chassis,
                onCommand = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    client.codexCommand(it)
                },
                onPttPress = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    ensureMicThen { client.pttStart() }
                },
                onPttRelease = { client.pttStopAndSend() },
            )

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedButton(onClick = { client.codexLayerCycle() }) {
                    Text(stringResource(R.string.codex_layer_fmt, state.layer))
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { client.requestCodexMicroState() }) {
                    Icon(Icons.Default.Refresh, contentDescription = null)
                }
            }

            StatusLegend()
        }
    }
}

@Composable
private fun ConnectionStatusCard(
    clientPhase: HubClientPhase,
    lockedTarget: HubCodexControlTarget,
    state: com.treelet.treelethub.hub.HubCodexMicroState,
    onFixPermission: () -> Unit,
    onEnableRetry: (HubCodexMicroAction?) -> Unit,
    onDismissHint: () -> Unit,
    chassis: Brush,
) {
    val installed =
        state.availableTargets.firstOrNull { it.target.bundleIdentifier == lockedTarget.bundleIdentifier }?.installed
            ?: (state.controlTarget.bundleIdentifier == lockedTarget.bundleIdentifier && state.targetInstalled)
    val running =
        state.availableTargets.firstOrNull { it.target.bundleIdentifier == lockedTarget.bundleIdentifier }?.running
            ?: (state.controlTarget.bundleIdentifier == lockedTarget.bundleIdentifier && state.targetRunning)

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(chassis)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        StatusLine(
            ok = clientPhase == HubClientPhase.Paired,
            label = stringResource(R.string.codex_link_phone_mac),
            value =
                stringResource(
                    if (clientPhase == HubClientPhase.Paired) R.string.codex_status_ok else R.string.codex_status_bad,
                ),
        )
        StatusLine(
            ok = installed,
            label = stringResource(R.string.codex_link_target_fmt, lockedTarget.displayNameEN),
            value =
                when {
                    !installed -> stringResource(R.string.codex_not_installed)
                    running -> stringResource(R.string.codex_running)
                    else -> stringResource(R.string.codex_installed_idle)
                },
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatusDot(state.accessibilityGranted)
            Text(
                stringResource(R.string.codex_link_accessibility),
                modifier = Modifier.weight(1f).padding(start = 8.dp),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (state.accessibilityGranted) {
                Text(
                    stringResource(R.string.codex_status_ok),
                    color = Color(0xFF4CAF50),
                    style = MaterialTheme.typography.labelMedium,
                )
            } else {
                Button(onClick = onFixPermission) {
                    Text(stringResource(R.string.codex_fix_permission))
                }
            }
        }

        val err = state.lastControlError
        if (!err.isNullOrBlank()) {
            val paletteQuery = paletteHintQuery(err)
            if (paletteQuery != null) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFFFF9800).copy(alpha = 0.12f))
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        stringResource(R.string.codex_palette_hint_title),
                        color = Color(0xFFFF9800),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    Text(
                        stringResource(R.string.codex_palette_hint_body_fmt, paletteQuery),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.7f),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onEnableRetry(actionMatchingPaletteQuery(paletteQuery)) }) {
                            Text(stringResource(R.string.codex_palette_enable_retry))
                        }
                        OutlinedButton(onClick = onDismissHint) {
                            Text(stringResource(R.string.codex_palette_dismiss))
                        }
                    }
                }
            } else {
                Text(err, color = Color(0xFFF44336), style = MaterialTheme.typography.bodySmall)
            }
        } else if (installed && state.accessibilityGranted) {
            Text(
                stringResource(R.string.codex_ready_hint),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.55f),
            )
        } else {
            Text(
                stringResource(R.string.codex_blocked_hint),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.55f),
            )
        }
    }
}

@Composable
private fun StatusLine(
    ok: Boolean,
    label: String,
    value: String,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        StatusDot(ok)
        Text(
            label,
            modifier = Modifier.weight(1f).padding(start = 8.dp),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            value,
            style = MaterialTheme.typography.labelMedium,
            color = if (ok) Color(0xFF4CAF50) else Color(0xFFFF9800),
        )
    }
}

@Composable
private fun StatusDot(ok: Boolean) {
    Box(
        Modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(if (ok) Color(0xFF4CAF50) else Color(0xFFFF9800)),
    )
}

@Composable
private fun HeaderRow(
    lockedTarget: HubCodexControlTarget,
    effectiveRecording: HubCodexRecordingState,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(lockedTarget.displayNameEN, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                when (lockedTarget) {
                    HubCodexControlTarget.Codex -> stringResource(R.string.codex_subtitle_codex)
                    HubCodexControlTarget.Cursor -> stringResource(R.string.codex_subtitle_cursor)
                    else -> stringResource(R.string.codex_subtitle_chatgpt)
                },
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.55f),
            )
        }
        when (effectiveRecording) {
            HubCodexRecordingState.Recording ->
                Text(
                    stringResource(R.string.codex_recording),
                    color = Color(0xFF26A69A),
                    style = MaterialTheme.typography.labelMedium,
                )
            HubCodexRecordingState.Processing ->
                Text(stringResource(R.string.codex_processing), style = MaterialTheme.typography.labelMedium)
            HubCodexRecordingState.Ready ->
                Text(stringResource(R.string.codex_ready_to_send), style = MaterialTheme.typography.labelMedium)
            else -> Unit
        }
    }
}

@Composable
private fun LiveTranscriptCard(
    phase: HubCodexRecordingState,
    partial: String,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF26A69A).copy(alpha = 0.12f))
            .border(1.dp, Color(0xFF26A69A).copy(alpha = 0.4f), RoundedCornerShape(14.dp))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Default.Mic, contentDescription = null, tint = Color(0xFF26A69A))
        Text(
            if (partial.isBlank()) stringResource(R.string.codex_listening) else partial,
            color = if (partial.isBlank()) Color.White.copy(alpha = 0.55f) else Color.White,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun AgentRow(
    agents: List<com.treelet.treelethub.hub.HubCodexAgentSlot>,
    brightness: Double,
    dialCancelArmed: Boolean,
    chassis: Brush,
    onTap: (Int) -> Unit,
) {
    val normalized =
        buildList {
            addAll(agents)
            while (size < 6) add(com.treelet.treelethub.hub.HubCodexAgentSlot(id = size))
        }.take(6)

    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(chassis)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        normalized.forEach { agent ->
            val glow =
                if (dialCancelArmed && agent.id == 0 && agent.status != HubCodexAgentStatus.Unassigned) {
                    Color.Red
                } else {
                    agentStatusColor(agent.status)
                }
            Column(
                Modifier
                    .weight(1f)
                    .height(72.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(glow.copy(alpha = if (agent.status == HubCodexAgentStatus.Unassigned) 0.08f else (0.45f * brightness).toFloat()))
                    .border(
                        width = if (agent.isSelected) 2.dp else 1.dp,
                        color = Color.White.copy(alpha = if (agent.isSelected) 0.55f else 0.12f),
                        shape = RoundedCornerShape(12.dp),
                    )
                    .pointerInput(agent.id) {
                        detectTapGestures { onTap(agent.id) }
                    }
                    .padding(6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("${agent.id + 1}", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                agent.title?.takeIf { it.isNotBlank() }?.let {
                    Text(it, fontSize = 9.sp, maxLines = 2, textAlign = TextAlign.Center, color = Color.White.copy(alpha = 0.75f))
                }
            }
        }
    }
}

@Composable
private fun ControlsRow(
    reasoningLevel: Int,
    dialMode: HubCodexDialMode,
    dialCancelArmed: Boolean,
    chassis: Brush,
    onDialTurn: (Int) -> Unit,
    onDialPress: () -> Unit,
    onDialLongPress: () -> Unit,
    onDialCancel: () -> Unit,
    onJoystick: (HubCodexJoystickDirection) -> Unit,
) {
    val view = LocalView.current
    val labels = listOf("Minimal", "Low", "Medium", "High", "xHigh")
    val idx = reasoningLevel.coerceIn(0, labels.lastIndex)

    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(chassis)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DialPad(
            modifier = Modifier.size(110.dp),
            onTurn = {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                onDialTurn(it)
            },
            onPress = {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onDialPress()
            },
            onLongPress = {
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                onDialLongPress()
            },
        )
        JoystickPad(
            modifier = Modifier.size(110.dp),
            onDirection = {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onJoystick(it)
            },
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(stringResource(R.string.codex_reasoning), style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.55f))
            Text(labels[idx], style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                if (dialMode == HubCodexDialMode.ReasoningOnly) {
                    stringResource(R.string.codex_dial_reasoning)
                } else {
                    stringResource(R.string.codex_dial_composer)
                },
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.45f),
            )
            if (dialCancelArmed) {
                OutlinedButton(onClick = onDialCancel) {
                    Text(stringResource(R.string.codex_cancel))
                }
            }
        }
    }
}

@Composable
private fun DialPad(
    modifier: Modifier,
    onTurn: (Int) -> Unit,
    onPress: () -> Unit,
    onLongPress: () -> Unit,
) {
    var dialAngle by remember { mutableFloatStateOf(0f) }
    var previousAngle by remember { mutableStateOf<Float?>(null) }
    var accumulator by remember { mutableFloatStateOf(0f) }
    var didRotate by remember { mutableStateOf(false) }
    var pressStartedAt by remember { mutableLongStateOf(0L) }
    val detent = 30f

    Box(
        modifier
            .clip(CircleShape)
            .background(
                Brush.linearGradient(listOf(Color(0xFF383838), Color(0xFF141414))),
            )
            .border(1.2.dp, Color.White.copy(alpha = 0.18f), CircleShape)
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = {
                        previousAngle = null
                        accumulator = 0f
                        didRotate = false
                        pressStartedAt = System.currentTimeMillis()
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        val center = Offset(size.width / 2f, size.height / 2f)
                        val angle =
                            Math.toDegrees(
                                atan2(
                                    (change.position.y - center.y).toDouble(),
                                    (change.position.x - center.x).toDouble(),
                                ),
                            ).toFloat()
                        val prev = previousAngle
                        if (prev == null) {
                            previousAngle = angle
                            return@detectDragGestures
                        }
                        var delta = angle - prev
                        if (delta > 180f) delta -= 360f
                        if (delta < -180f) delta += 360f
                        previousAngle = angle
                        dialAngle += delta
                        accumulator += delta
                        didRotate = true
                        while (kotlin.math.abs(accumulator) >= detent) {
                            val direction = if (accumulator > 0) 1 else -1
                            accumulator -= direction * detent
                            onTurn(direction)
                        }
                    },
                    onDragEnd = {
                        previousAngle = null
                        accumulator = 0f
                        val held = System.currentTimeMillis() - pressStartedAt
                        if (!didRotate) {
                            if (held >= 500) onLongPress() else onPress()
                        }
                        didRotate = false
                    },
                    onDragCancel = {
                        previousAngle = null
                        accumulator = 0f
                        didRotate = false
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(4.dp, 22.dp)
                .offset { IntOffset(0, (-34).dp.roundToPx()) }
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White.copy(alpha = 0.85f)),
        )
        Box(
            Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(Color(0xFF242424))
                .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape),
        )
    }
}

@Composable
private fun JoystickPad(
    modifier: Modifier,
    onDirection: (HubCodexJoystickDirection) -> Unit,
) {
    var offset by remember { mutableStateOf(Offset.Zero) }
    Box(
        modifier
            .clip(RoundedCornerShape(28.dp))
            .background(Color(0xFF1A1A1A))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(28.dp))
            .pointerInput(Unit) {
                detectDragGestures(
                    onDrag = { change, drag ->
                        change.consume()
                        val next = offset + drag
                        offset =
                            Offset(
                                next.x.coerceIn(-28f, 28f),
                                next.y.coerceIn(-28f, 28f),
                            )
                    },
                    onDragEnd = {
                        if (hypot(offset.x.toDouble(), offset.y.toDouble()) >= 24) {
                            val dir =
                                if (kotlin.math.abs(offset.x) > kotlin.math.abs(offset.y)) {
                                    if (offset.x > 0) HubCodexJoystickDirection.Right else HubCodexJoystickDirection.Left
                                } else {
                                    if (offset.y > 0) HubCodexJoystickDirection.Down else HubCodexJoystickDirection.Up
                                }
                            onDirection(dir)
                        }
                        offset = Offset.Zero
                    },
                    onDragCancel = { offset = Offset.Zero },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .offset { IntOffset(offset.x.roundToInt(), offset.y.roundToInt()) }
                .size(64.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(listOf(Color(0xFF595959), Color(0xFF1F1F1F))),
                ),
        )
    }
}

@Composable
private fun CommandGrid(
    keys: List<HubCodexMicroAction>,
    isRecording: Boolean,
    chassis: Brush,
    onCommand: (HubCodexMicroAction) -> Unit,
    onPttPress: () -> Unit,
    onPttRelease: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(chassis)
            .padding(12.dp),
    ) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.height(260.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            userScrollEnabled = false,
        ) {
            itemsIndexed(keys) { _, action ->
                if (action == HubCodexMicroAction.PushToTalk) {
                    PushToTalkKey(
                        isRecording = isRecording,
                        onPress = onPttPress,
                        onRelease = onPttRelease,
                    )
                } else {
                    CommandKey(action = action, onTap = { onCommand(action) })
                }
            }
        }
    }
}

@Composable
private fun CommandKey(
    action: HubCodexMicroAction,
    onTap: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .height(78.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(16.dp))
            .pointerInput(action) { detectTapGestures { onTap() } }
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(shortActionLabel(action), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}

@Composable
private fun PushToTalkKey(
    isRecording: Boolean,
    onPress: () -> Unit,
    onRelease: () -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    var handsFree by remember { mutableStateOf(false) }
    var localActive by remember { mutableStateOf(false) }
    var lastDownAt by remember { mutableLongStateOf(0L) }
    var pressBeganAt by remember { mutableLongStateOf(0L) }
    val scope = rememberCoroutineScope()
    var pendingJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    val showListening = localActive || isRecording

    Column(
        Modifier
            .fillMaxWidth()
            .height(78.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (showListening) Color(0xFF26A69A).copy(alpha = 0.35f) else Color.White.copy(alpha = 0.08f))
            .border(
                1.dp,
                if (showListening) Color(0xFF26A69A).copy(alpha = 0.8f) else Color.White.copy(alpha = 0.14f),
                RoundedCornerShape(16.dp),
            )
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = {
                        pressed = true
                        val now = System.currentTimeMillis()
                        pressBeganAt = now
                        if (handsFree && (localActive || isRecording)) {
                            pendingJob?.cancel()
                            handsFree = false
                            localActive = false
                            lastDownAt = 0L
                            onRelease()
                            return@detectDragGestures
                        }
                        if (lastDownAt > 0 && now - lastDownAt < 350) {
                            pendingJob?.cancel()
                            handsFree = true
                            if (!localActive) {
                                localActive = true
                                onPress()
                            }
                            lastDownAt = now
                            return@detectDragGestures
                        }
                        pendingJob?.cancel()
                        lastDownAt = now
                        handsFree = false
                        localActive = true
                        onPress()
                    },
                    onDrag = { change, _ -> change.consume() },
                    onDragEnd = {
                        pressed = false
                        if (handsFree) return@detectDragGestures
                        if (!localActive) return@detectDragGestures
                        val heldFor = System.currentTimeMillis() - pressBeganAt
                        if (heldFor >= 280) {
                            pendingJob?.cancel()
                            localActive = false
                            lastDownAt = 0L
                            onRelease()
                        } else {
                            pendingJob?.cancel()
                            pendingJob =
                                scope.launch {
                                    delay(350)
                                    if (!handsFree && localActive) {
                                        localActive = false
                                        lastDownAt = 0L
                                        onRelease()
                                    }
                                }
                        }
                    },
                    onDragCancel = { pressed = false },
                )
            }
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Default.Mic, contentDescription = null, tint = Color.White)
        Text(
            when {
                showListening && handsFree -> stringResource(R.string.codex_ptt_handsfree)
                showListening -> stringResource(R.string.codex_ptt_listening)
                else -> "PTT"
            },
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            if (handsFree) stringResource(R.string.codex_ptt_hint_handsfree) else stringResource(R.string.codex_ptt_hint_hold),
            style = MaterialTheme.typography.labelSmall,
            fontSize = 8.sp,
            color = Color.White.copy(alpha = 0.55f),
            maxLines = 1,
        )
    }
}

@Composable
private fun StatusLegend() {
    val items =
        listOf(
            HubCodexAgentStatus.Idle to R.string.codex_status_idle,
            HubCodexAgentStatus.Thinking to R.string.codex_status_thinking,
            HubCodexAgentStatus.Complete to R.string.codex_status_complete,
            HubCodexAgentStatus.RequiresInput to R.string.codex_status_input,
            HubCodexAgentStatus.Error to R.string.codex_status_error,
        )
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items.forEach { (status, res) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(agentStatusColor(status)))
                Text(stringResource(res), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.55f))
            }
        }
    }
}

@Composable
fun HubCodexMicroSettingsScreen(
    client: HubAndroidClient,
    lockedTarget: HubCodexControlTarget,
    onDismiss: () -> Unit,
) {
    val ui by client.state.collectAsStateWithLifecycle()
    var mapping by remember {
        mutableStateOf(
            if (ui.codexMicroState.controlTarget == lockedTarget) {
                ui.codexMicroState.mapping
            } else {
                HubCodexMicroMapping.default(lockedTarget)
            },
        )
    }
    var editingCommandIndex by remember { mutableStateOf<Int?>(null) }
    var editingJoystick by remember { mutableStateOf<HubCodexJoystickDirection?>(null) }

    val keys =
        remember(mapping, lockedTarget) {
            val k = mapping.commandKeys
            if (k.size == 6) k else HubCodexMicroMapping.defaultCommandKeys(lockedTarget)
        }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.codex_settings)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.common_cancel))
                    }
                },
                actions = {
                    TextButton(
                        onClick = {
                            client.codexSetMapping(mapping.copy(commandKeys = keys))
                            onDismiss()
                        },
                    ) {
                        Text(stringResource(R.string.codex_save))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.codex_control_target), style = MaterialTheme.typography.titleSmall)
            Text(lockedTarget.displayNameEN, color = MaterialTheme.colorScheme.onSurfaceVariant)

            if (lockedTarget.showsAgentKeys) {
                Text(stringResource(R.string.codex_agent_source), style = MaterialTheme.typography.titleSmall)
                AgentSourceChips(mapping.agentSource) { mapping = mapping.copy(agentSource = it) }
            }

            Text(stringResource(R.string.codex_dial_mode), style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = mapping.dialMode == HubCodexDialMode.ReasoningOnly,
                    onClick = { mapping = mapping.copy(dialMode = HubCodexDialMode.ReasoningOnly) },
                    label = { Text(stringResource(R.string.codex_dial_reasoning)) },
                )
                FilterChip(
                    selected = mapping.dialMode == HubCodexDialMode.ComposerNavigation,
                    onClick = { mapping = mapping.copy(dialMode = HubCodexDialMode.ComposerNavigation) },
                    label = { Text(stringResource(R.string.codex_dial_composer)) },
                )
            }

            Text(stringResource(R.string.codex_brightness))
            Slider(
                value = mapping.brightness.toFloat().coerceIn(0.2f, 1f),
                onValueChange = { mapping = mapping.copy(brightness = it.toDouble()) },
                valueRange = 0.2f..1f,
            )

            Text(stringResource(R.string.codex_idle_lights_fmt, mapping.idleLightSeconds))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        mapping = mapping.copy(idleLightSeconds = (mapping.idleLightSeconds - 30).coerceAtLeast(30))
                    },
                ) { Text("-30") }
                OutlinedButton(
                    onClick = {
                        mapping = mapping.copy(idleLightSeconds = (mapping.idleLightSeconds + 30).coerceAtMost(600))
                    },
                ) { Text("+30") }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.codex_text_automation), modifier = Modifier.weight(1f))
                Switch(
                    checked = mapping.allowsTextAutomation,
                    onCheckedChange = { mapping = mapping.copy(allowsTextAutomation = it) },
                )
            }
            Text(
                stringResource(R.string.codex_text_automation_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HorizontalDivider()
            Text(stringResource(R.string.codex_command_keys), style = MaterialTheme.typography.titleSmall)
            keys.forEachIndexed { index, action ->
                TextButton(onClick = { editingCommandIndex = index; editingJoystick = null }) {
                    Text("${stringResource(R.string.codex_key_n, index + 1)} · ${actionTitle(action, lockedTarget)}")
                }
            }

            Text(stringResource(R.string.codex_joystick_map), style = MaterialTheme.typography.titleSmall)
            HubCodexJoystickDirection.entries.forEach { direction ->
                val action =
                    mapping.joystick[directionSerial(direction)]
                        ?: HubCodexMicroMapping.defaultJoystick(lockedTarget)[directionSerial(direction)]
                        ?: HubCodexMicroAction.None
                TextButton(onClick = { editingJoystick = direction; editingCommandIndex = null }) {
                    Text("${directionTitle(direction)} · ${actionTitle(action, lockedTarget)}")
                }
            }

            TextButton(
                onClick = { mapping = HubCodexMicroMapping.default(lockedTarget) },
            ) {
                Text(stringResource(R.string.codex_reset_defaults), color = MaterialTheme.colorScheme.error)
            }
        }
    }

    val picking = editingCommandIndex != null || editingJoystick != null
    if (picking) {
        AlertDialog(
            onDismissRequest = {
                editingCommandIndex = null
                editingJoystick = null
            },
            title = { Text(stringResource(R.string.codex_settings)) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    HubCodexMicroMapping.remappableActions(lockedTarget).forEach { action ->
                        TextButton(
                            onClick = {
                                val idx = editingCommandIndex
                                val dir = editingJoystick
                                if (idx != null) {
                                    val next = keys.toMutableList()
                                    next[idx] = action
                                    mapping = mapping.copy(commandKeys = next)
                                } else if (dir != null) {
                                    mapping =
                                        mapping.copy(
                                            joystick = mapping.joystick + (directionSerial(dir) to action),
                                        )
                                }
                                editingCommandIndex = null
                                editingJoystick = null
                            },
                        ) {
                            Text(actionTitle(action, lockedTarget))
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    editingCommandIndex = null
                    editingJoystick = null
                }) { Text(stringResource(R.string.common_cancel)) }
            },
        )
    }
}

@Composable
private fun AgentSourceChips(
    selected: HubCodexAgentSource,
    onSelect: (HubCodexAgentSource) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(
            HubCodexAgentSource.MostRecent to R.string.codex_source_recent,
            HubCodexAgentSource.Pinned to R.string.codex_source_pinned,
            HubCodexAgentSource.Priority to R.string.codex_source_priority,
            HubCodexAgentSource.Custom to R.string.codex_source_custom,
        ).forEach { (src, res) ->
            FilterChip(
                selected = selected == src,
                onClick = { onSelect(src) },
                label = { Text(stringResource(res)) },
            )
        }
    }
}

private fun normalizedCommandKeys(
    state: com.treelet.treelethub.hub.HubCodexMicroState,
    lockedTarget: HubCodexControlTarget,
): List<HubCodexMicroAction> {
    if (state.controlTarget == lockedTarget && state.mapping.commandKeys.size == 6) {
        return state.mapping.commandKeys
    }
    return HubCodexMicroMapping.defaultCommandKeys(lockedTarget)
}

private fun agentStatusColor(status: HubCodexAgentStatus): Color =
    when (status) {
        HubCodexAgentStatus.Idle -> Color(0xFFEBEBEB)
        HubCodexAgentStatus.Thinking -> Color(0xFF408CFF)
        HubCodexAgentStatus.Complete -> Color(0xFF40D173)
        HubCodexAgentStatus.RequiresInput -> Color(0xFFFFB82E)
        HubCodexAgentStatus.Error -> Color(0xFFF24747)
        HubCodexAgentStatus.Unassigned -> Color.Transparent
    }

private fun paletteHintQuery(message: String): String? {
    val prefix = "hint:palette:"
    return if (message.startsWith(prefix)) message.removePrefix(prefix) else null
}

private fun actionMatchingPaletteQuery(query: String): HubCodexMicroAction? {
    val q = query.lowercase()
    return when {
        q.contains("fast") -> HubCodexMicroAction.FastMode
        q.contains("approve") -> HubCodexMicroAction.Approve
        q.contains("decline") -> HubCodexMicroAction.Decline
        q.contains("plan") -> HubCodexMicroAction.PlanMode
        q.contains("browser") -> HubCodexMicroAction.OpenBrowser
        q.contains("commit") -> HubCodexMicroAction.GitCommit
        q.contains("pull") -> HubCodexMicroAction.CreatePullRequest
        q.contains("skill") -> HubCodexMicroAction.OpenSkills
        q.contains("schedul") -> HubCodexMicroAction.ScheduledTasks
        q.contains("reasoning") -> HubCodexMicroAction.ReasoningEffort
        else -> null
    }
}

private fun shortActionLabel(action: HubCodexMicroAction): String =
    when (action) {
        HubCodexMicroAction.FastMode -> "Fast"
        HubCodexMicroAction.Approve -> "Approve"
        HubCodexMicroAction.Decline -> "Decline"
        HubCodexMicroAction.ContinueNewChat -> "Continue"
        HubCodexMicroAction.PushToTalk -> "PTT"
        HubCodexMicroAction.SendMessage -> "Send"
        HubCodexMicroAction.NewChat -> "New"
        HubCodexMicroAction.OpenBrowser -> "Browser"
        HubCodexMicroAction.OpenTerminal -> "Terminal"
        HubCodexMicroAction.ReviewChanges -> "Review"
        HubCodexMicroAction.GitCommit -> "Commit"
        HubCodexMicroAction.CreatePullRequest -> "PR"
        HubCodexMicroAction.AttachFiles -> "Attach"
        HubCodexMicroAction.ScheduledTasks -> "Schedule"
        HubCodexMicroAction.ReasoningEffort -> "Reason"
        HubCodexMicroAction.OpenSkills -> "Skills"
        HubCodexMicroAction.PlanMode -> "Plan"
        HubCodexMicroAction.HistoryBack -> "Back"
        HubCodexMicroAction.HistoryForward -> "Forward"
        HubCodexMicroAction.ToggleSidebar -> "Sidebar"
        HubCodexMicroAction.OpenSettings -> "Settings"
        HubCodexMicroAction.OpenCommandMenu -> "Menu"
        HubCodexMicroAction.FocusChatGPT -> "Chat"
        HubCodexMicroAction.None -> "—"
    }

@Composable
private fun actionTitle(
    action: HubCodexMicroAction,
    lockedTarget: HubCodexControlTarget,
): String =
    when (action) {
        HubCodexMicroAction.FastMode -> stringResource(R.string.codex_action_fast)
        HubCodexMicroAction.Approve ->
            stringResource(if (lockedTarget == HubCodexControlTarget.Cursor) R.string.codex_action_accept else R.string.codex_action_approve)
        HubCodexMicroAction.Decline ->
            stringResource(if (lockedTarget == HubCodexControlTarget.Cursor) R.string.codex_action_reject else R.string.codex_action_decline)
        HubCodexMicroAction.ContinueNewChat -> stringResource(R.string.codex_action_continue)
        HubCodexMicroAction.PushToTalk -> stringResource(R.string.codex_action_ptt)
        HubCodexMicroAction.SendMessage -> stringResource(R.string.codex_action_send)
        HubCodexMicroAction.NewChat -> stringResource(R.string.codex_action_new)
        HubCodexMicroAction.OpenBrowser -> stringResource(R.string.codex_action_browser)
        HubCodexMicroAction.OpenTerminal -> stringResource(R.string.codex_action_terminal)
        HubCodexMicroAction.ReviewChanges -> stringResource(R.string.codex_action_review)
        HubCodexMicroAction.GitCommit -> stringResource(R.string.codex_action_commit)
        HubCodexMicroAction.CreatePullRequest -> stringResource(R.string.codex_action_pr)
        HubCodexMicroAction.AttachFiles -> stringResource(R.string.codex_action_attach)
        HubCodexMicroAction.ScheduledTasks -> stringResource(R.string.codex_action_schedule)
        HubCodexMicroAction.ReasoningEffort -> stringResource(R.string.codex_action_reasoning)
        HubCodexMicroAction.OpenSkills -> stringResource(R.string.codex_action_skills)
        HubCodexMicroAction.PlanMode -> stringResource(R.string.codex_action_plan)
        HubCodexMicroAction.HistoryBack -> stringResource(R.string.codex_action_back)
        HubCodexMicroAction.HistoryForward -> stringResource(R.string.codex_action_forward)
        HubCodexMicroAction.ToggleSidebar -> stringResource(R.string.codex_action_sidebar)
        HubCodexMicroAction.OpenSettings -> stringResource(R.string.codex_action_settings)
        HubCodexMicroAction.OpenCommandMenu -> stringResource(R.string.codex_action_menu)
        HubCodexMicroAction.FocusChatGPT ->
            stringResource(if (lockedTarget == HubCodexControlTarget.Cursor) R.string.codex_action_chat else R.string.codex_action_focus)
        HubCodexMicroAction.None -> "—"
    }

@Composable
private fun directionTitle(direction: HubCodexJoystickDirection): String =
    when (direction) {
        HubCodexJoystickDirection.Up -> stringResource(R.string.codex_joy_up)
        HubCodexJoystickDirection.Right -> stringResource(R.string.codex_joy_right)
        HubCodexJoystickDirection.Down -> stringResource(R.string.codex_joy_down)
        HubCodexJoystickDirection.Left -> stringResource(R.string.codex_joy_left)
    }

private fun directionSerial(direction: HubCodexJoystickDirection): String =
    when (direction) {
        HubCodexJoystickDirection.Up -> "up"
        HubCodexJoystickDirection.Right -> "right"
        HubCodexJoystickDirection.Down -> "down"
        HubCodexJoystickDirection.Left -> "left"
    }
