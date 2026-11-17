package com.treelet.treelethub.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.treelet.treelethub.R
import com.treelet.treelethub.hub.HubAndroidClient
import com.treelet.treelethub.hub.HubRemoteInputCommands

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HubRemoteInputScreen(
    client: HubAndroidClient,
    available: Boolean,
    lastError: String?,
    onDismiss: () -> Unit,
) {
    var draft by remember { mutableStateOf("") }
    var held by remember { mutableStateOf(setOf<String>()) }
    val movePump = remember { RemoteMovePump() }

    fun send(
        command: String,
        dx: Double? = null,
        dy: Double? = null,
        button: String? = null,
        key: String? = null,
        message: String? = null,
    ) {
        if (!available) return
        client.sendRemoteInput(command, dx, dy, button, key, message)
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.input_title)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.common_back),
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
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!available) {
                Text(
                    stringResource(R.string.input_need_pro),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainer)
                            .padding(12.dp),
                )
            }
            Text(
                stringResource(R.string.input_trackpad_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            androidx.compose.foundation.layout.Box(
                Modifier
                    .fillMaxWidth()
                    .height(220.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerLow)
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
                    .pointerInput(available) {
                        if (!available) return@pointerInput
                        awaitEachGesture {
                            val first = awaitFirstDown(requireUnconsumed = false)
                            var last = first.position
                            var total = Offset.Zero
                            var scrolling = false
                            while (true) {
                                val event = awaitPointerEvent()
                                val pressed = event.changes.filter { it.pressed }
                                if (pressed.isEmpty()) {
                                    if (!scrolling && total.getDistance() < 12f) {
                                        send(HubRemoteInputCommands.click, button = "left")
                                    } else if (!scrolling) {
                                        movePump.flush { x, y ->
                                            send(HubRemoteInputCommands.move, dx = x.toDouble(), dy = y.toDouble())
                                        }
                                    }
                                    break
                                }
                                if (pressed.size >= 2) {
                                    scrolling = true
                                    val centroid =
                                        pressed.fold(Offset.Zero) { acc, change -> acc + change.position } /
                                            pressed.size.toFloat()
                                    val delta = centroid - last
                                    last = centroid
                                    pressed.forEach { it.consume() }
                                    if (delta != Offset.Zero) {
                                        send(
                                            HubRemoteInputCommands.scroll,
                                            dx = delta.x.toDouble(),
                                            dy = delta.y.toDouble(),
                                        )
                                    }
                                } else {
                                    val change = pressed.first()
                                    val delta = change.position - last
                                    last = change.position
                                    total += delta
                                    change.consume()
                                    if (!scrolling && total.getDistance() > 8f && delta != Offset.Zero) {
                                        movePump.add(delta.x * 1.5f, delta.y * 1.5f) { x, y ->
                                            send(HubRemoteInputCommands.move, dx = x.toDouble(), dy = y.toDouble())
                                        }
                                    }
                                }
                            }
                        }
                    },
            )
            Button(
                onClick = { send(HubRemoteInputCommands.click, button = "right") },
                enabled = available,
            ) {
                Text(stringResource(R.string.input_right_click))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ModifierKey("command", "⌘", held, available) { next, down ->
                    held = next
                    send(if (down) HubRemoteInputCommands.keyDown else HubRemoteInputCommands.keyUp, key = "command")
                }
                ModifierKey("option", "⌥", held, available) { next, down ->
                    held = next
                    send(if (down) HubRemoteInputCommands.keyDown else HubRemoteInputCommands.keyUp, key = "option")
                }
                ModifierKey("control", "⌃", held, available) { next, down ->
                    held = next
                    send(if (down) HubRemoteInputCommands.keyDown else HubRemoteInputCommands.keyUp, key = "control")
                }
                ModifierKey("shift", "⇧", held, available) { next, down ->
                    held = next
                    send(if (down) HubRemoteInputCommands.keyDown else HubRemoteInputCommands.keyUp, key = "shift")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MomentaryKey(stringResource(R.string.input_key_esc), available) { tapKey(available, client, "escape") }
                MomentaryKey(stringResource(R.string.input_key_tab), available) { tapKey(available, client, "tab") }
                MomentaryKey(stringResource(R.string.input_key_delete), available) { tapKey(available, client, "delete") }
                MomentaryKey(stringResource(R.string.input_key_return), available) { tapKey(available, client, "return") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MomentaryKey("←", available) { tapKey(available, client, "left") }
                MomentaryKey("↑", available) { tapKey(available, client, "up") }
                MomentaryKey("↓", available) { tapKey(available, client, "down") }
                MomentaryKey("→", available) { tapKey(available, client, "right") }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.weight(1f),
                    enabled = available,
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.input_text_placeholder)) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions =
                        KeyboardActions(
                            onSend = {
                                if (draft.isNotEmpty() && available) {
                                    client.sendRemoteInput(HubRemoteInputCommands.text, message = draft)
                                    draft = ""
                                }
                            },
                        ),
                )
                Button(
                    onClick = {
                        if (draft.isNotEmpty()) {
                            send(HubRemoteInputCommands.text, message = draft)
                            draft = ""
                        }
                    },
                    enabled = available && draft.isNotEmpty(),
                ) {
                    Text(stringResource(R.string.input_send))
                }
            }
            if (!lastError.isNullOrBlank()) {
                Text(lastError, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun ModifierKey(
    name: String,
    label: String,
    held: Set<String>,
    enabled: Boolean,
    onToggle: (Set<String>, Boolean) -> Unit,
) {
    val on = held.contains(name)
    FilledTonalButton(
        onClick = {
            val next = if (on) held - name else held + name
            onToggle(next, !on)
        },
        enabled = enabled,
    ) {
        Text(label)
    }
}

@Composable
private fun MomentaryKey(
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    FilledTonalButton(onClick = onClick, enabled = enabled) {
        Text(label)
    }
}

private fun tapKey(available: Boolean, client: HubAndroidClient, key: String) {
    if (!available) return
    client.sendRemoteInput(HubRemoteInputCommands.keyDown, key = key)
    client.sendRemoteInput(HubRemoteInputCommands.keyUp, key = key)
}

private class RemoteMovePump {
    private var dx = 0f
    private var dy = 0f
    private var lastSent = 0L

    fun add(x: Float, y: Float, send: (Float, Float) -> Unit) {
        dx += x
        dy += y
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastSent >= 16L) flush(send)
    }

    fun flush(send: (Float, Float) -> Unit) {
        if (dx == 0f && dy == 0f) return
        val x = dx
        val y = dy
        dx = 0f
        dy = 0f
        lastSent = android.os.SystemClock.uptimeMillis()
        send(x, y)
    }
}
