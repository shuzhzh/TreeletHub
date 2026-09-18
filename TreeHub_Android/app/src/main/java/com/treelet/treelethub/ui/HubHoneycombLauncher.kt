package com.treelet.treelethub.ui

import android.content.Context
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Hexagon
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.treelet.treelethub.hub.HubHoneycombLayout
import com.treelet.treelethub.hub.HubLauncherItem
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.withTimeoutOrNull

private const val DefaultPersistenceKey = "treelethub.launcher.android"
private const val LongPressMs = 480L
private const val MoveThresholdPx = 6f

private enum class GestureKind {
    Undecided,
    Pan,
    IconDrag,
}

/**
 * Watch App View 风格蜂巢启动墙（对齐 iOS HubHoneycombLauncherCanvas）。
 */
@Composable
fun HubHoneycombLauncher(
    items: List<HubLauncherItem>,
    emptyHint: String,
    reduceMotion: Boolean,
    animatingItemId: String?,
    editDoneLabel: String,
    onSelect: (HubLauncherItem) -> Unit,
    onReorder: (HubLauncherItem, HubLauncherItem) -> Unit,
    modifier: Modifier = Modifier,
    persistenceKey: String = DefaultPersistenceKey,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs =
        remember(persistenceKey) {
            context.getSharedPreferences(persistenceKey, Context.MODE_PRIVATE)
        }
    val view = LocalView.current
    val density = LocalDensity.current

    var scale by remember { mutableFloatStateOf(HubHoneycombLayout.defaultScale) }
    var committedScale by remember { mutableFloatStateOf(HubHoneycombLayout.defaultScale) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var committedOffsetX by remember { mutableFloatStateOf(0f) }
    var committedOffsetY by remember { mutableFloatStateOf(0f) }
    var viewportW by remember { mutableFloatStateOf(0f) }
    var viewportH by remember { mutableFloatStateOf(0f) }
    var didLoadPersistence by remember { mutableStateOf(false) }

    var isEditing by remember { mutableStateOf(false) }
    var draggingItemId by remember { mutableStateOf<String?>(null) }
    var dragFinger by remember { mutableStateOf(Offset.Zero) }
    var dropTargetId by remember { mutableStateOf<String?>(null) }
    var lastBlankTapAt by remember { mutableLongStateOf(0L) }

    // 与 iOS 一致：defaultBaseIconSide 是逻辑点（dp），再换算成像素做世界坐标。
    val baseIconSidePx = with(density) { HubHoneycombLayout.defaultBaseIconSide.dp.toPx() }
    val minIconSidePx = with(density) { 22.dp.toPx() }
    val hexSpacing = HubHoneycombLayout.spacing(baseIconSidePx)
    val positions =
        remember(items.size, baseIconSidePx) {
            HubHoneycombLayout.spiralPositions(max(items.size, 1), hexSpacing)
        }

    fun softClamp() {
        if (viewportW <= 1f || viewportH <= 1f) return
        val bounds = HubHoneycombLayout.contentBounds(positions, baseIconSidePx)
        val limitX = max(bounds.width * scale * 0.55f, viewportW * 0.35f)
        val limitY = max(bounds.height * scale * 0.55f, viewportH * 0.35f)
        offsetX = min(limitX, max(-limitX, offsetX))
        offsetY = min(limitY, max(-limitY, offsetY))
    }

    fun persist() {
        prefs
            .edit()
            .putFloat("$persistenceKey.scale", scale)
            .putFloat("$persistenceKey.ox", offsetX)
            .putFloat("$persistenceKey.oy", offsetY)
            .putBoolean("$persistenceKey.ready", true)
            .putInt("$persistenceKey.layoutRev", HubHoneycombLayout.layoutRevision)
            .apply()
    }

    fun loadOrInit(
        w: Float,
        h: Float,
    ) {
        if (w <= 1f || h <= 1f) return
        val ready = prefs.getBoolean("$persistenceKey.ready", false)
        val rev = prefs.getInt("$persistenceKey.layoutRev", 0)
        if (ready && rev == HubHoneycombLayout.layoutRevision) {
            scale = prefs.getFloat("$persistenceKey.scale", HubHoneycombLayout.defaultScale)
            committedScale = scale
            offsetX = prefs.getFloat("$persistenceKey.ox", 0f)
            offsetY = prefs.getFloat("$persistenceKey.oy", HubHoneycombLayout.defaultOffsetY(h))
            committedOffsetX = offsetX
            committedOffsetY = offsetY
            softClamp()
            committedOffsetX = offsetX
            committedOffsetY = offsetY
        } else {
            scale = HubHoneycombLayout.defaultScale
            committedScale = scale
            offsetX = 0f
            offsetY = HubHoneycombLayout.defaultOffsetY(h)
            committedOffsetX = offsetX
            committedOffsetY = offsetY
            persist()
        }
        didLoadPersistence = true
    }

    fun recenter() {
        scale = HubHoneycombLayout.defaultScale
        committedScale = scale
        offsetX = 0f
        offsetY = HubHoneycombLayout.defaultOffsetY(viewportH)
        committedOffsetX = offsetX
        committedOffsetY = offsetY
        persist()
    }

    fun hitTest(at: Offset): HubLauncherItem? {
        if (items.isEmpty()) return null
        var best: Pair<HubLauncherItem, Float>? = null
        items.forEachIndexed { index, item ->
            val pos = positions[index]
            val focus =
                HubHoneycombLayout.focusScale(
                    worldPosition = pos,
                    scale = scale,
                    offsetX = offsetX,
                    offsetY = offsetY,
                    viewport = HubHoneycombLayout.Size(viewportW, viewportH),
                    spacing = hexSpacing,
                )
            val side = max(minIconSidePx, baseIconSidePx * scale * focus)
            val center =
                Offset(
                    viewportW * 0.5f + pos.x * scale + offsetX,
                    viewportH * 0.5f + pos.y * scale + offsetY,
                )
            val dist = hypot(at.x - center.x, at.y - center.y)
            if (dist <= side * 0.58f) {
                if (best == null || dist < best!!.second) {
                    best = item to dist
                }
            }
        }
        return best?.first
    }

    val itemsLatest by rememberUpdatedState(items)
    val onSelectLatest by rememberUpdatedState(onSelect)
    val onReorderLatest by rememberUpdatedState(onReorder)
    val isEditingLatest by rememberUpdatedState(isEditing)

    LaunchedEffect(items.size) {
        if (items.isEmpty() && isEditing) {
            isEditing = false
            draggingItemId = null
            dropTargetId = null
        }
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        LaunchedEffect(w, h) {
            viewportW = w
            viewportH = h
            if (!didLoadPersistence) loadOrInit(w, h)
        }

        val jiggle =
            if (isEditing && !reduceMotion) {
                val transition = rememberInfiniteTransition(label = "jiggle")
                transition
                    .animateFloat(
                        initialValue = -1.8f,
                        targetValue = 1.8f,
                        animationSpec =
                            infiniteRepeatable(
                                animation = tween(120),
                                repeatMode = RepeatMode.Reverse,
                            ),
                        label = "jiggleRot",
                    ).value
            } else {
                0f
            }

        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val startPos = down.position
                        var pressCandidate = hitTest(startPos)
                        var gestureKind = GestureKind.Undecided
                        var startedDragItem: HubLauncherItem? = null
                        var longPressFired = false
                        val canLongPress =
                            !isEditingLatest &&
                                pressCandidate != null &&
                                !pressCandidate!!.slot.isEmpty

                        if (canLongPress) {
                            val timedOut =
                                withTimeoutOrNull(LongPressMs) {
                                    while (true) {
                                        val event = awaitPointerEvent()
                                        val change = event.changes.firstOrNull { it.id == down.id }
                                        if (change == null || !change.pressed) return@withTimeoutOrNull false
                                        val dist =
                                            hypot(
                                                change.position.x - startPos.x,
                                                change.position.y - startPos.y,
                                            )
                                        if (dist > MoveThresholdPx) return@withTimeoutOrNull false
                                        if (event.changes.any { it.pressed && it.id != down.id }) {
                                            return@withTimeoutOrNull false
                                        }
                                    }
                                    @Suppress("UNREACHABLE_CODE")
                                    false
                                }
                            if (timedOut == null) {
                                longPressFired = true
                                isEditing = true
                                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                gestureKind = GestureKind.IconDrag
                                startedDragItem = pressCandidate
                                draggingItemId = pressCandidate!!.id
                                dragFinger = startPos
                                dropTargetId = null
                            }
                        }

                        try {
                            while (true) {
                                val event = awaitPointerEvent()
                                val pressed = event.changes.filter { it.pressed }
                                if (pressed.isEmpty()) break

                                val zoom = event.calculateZoom()
                                val pan = event.calculatePan()
                                val multiTouch = pressed.size >= 2

                                if (multiTouch) {
                                    gestureKind = GestureKind.Pan
                                    if (zoom != 1f) {
                                        scale =
                                            (scale * zoom).coerceIn(
                                                HubHoneycombLayout.defaultMinScale,
                                                HubHoneycombLayout.defaultMaxScale,
                                            )
                                        committedScale = scale
                                    }
                                    if (pan != Offset.Zero) {
                                        offsetX += pan.x
                                        offsetY += pan.y
                                    }
                                    event.changes.forEach {
                                        if (it.positionChanged()) it.consume()
                                    }
                                    continue
                                }

                                val change = pressed.first()
                                val delta = change.position - startPos
                                val distance = hypot(delta.x, delta.y)

                                if (gestureKind == GestureKind.Undecided && distance > MoveThresholdPx) {
                                    if (isEditingLatest &&
                                        pressCandidate != null &&
                                        !pressCandidate!!.slot.isEmpty
                                    ) {
                                        gestureKind = GestureKind.IconDrag
                                        startedDragItem = pressCandidate
                                        draggingItemId = pressCandidate!!.id
                                        dragFinger = change.position
                                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                    } else {
                                        gestureKind = GestureKind.Pan
                                    }
                                }

                                when (gestureKind) {
                                    GestureKind.Pan -> {
                                        offsetX = committedOffsetX + delta.x
                                        offsetY = committedOffsetY + delta.y
                                    }
                                    GestureKind.IconDrag -> {
                                        dragFinger = change.position
                                        val hit = hitTest(change.position)
                                        dropTargetId =
                                            hit
                                                ?.takeIf { it.id != draggingItemId && !it.slot.isEmpty }
                                                ?.id
                                    }
                                    GestureKind.Undecided -> Unit
                                }
                                if (change.positionChanged()) change.consume()
                            }
                        } finally {
                            // gesture ended
                        }

                        when (gestureKind) {
                            GestureKind.IconDrag -> {
                                val source =
                                    startedDragItem
                                        ?: itemsLatest.firstOrNull { it.id == draggingItemId }
                                val target =
                                    itemsLatest.firstOrNull { it.id == dropTargetId }
                                        ?: hitTest(dragFinger)
                                if (source != null &&
                                    target != null &&
                                    source.id != target.id &&
                                    !target.slot.isEmpty
                                ) {
                                    onReorderLatest(source, target)
                                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                                }
                                draggingItemId = null
                                dropTargetId = null
                            }
                            GestureKind.Pan -> {
                                softClamp()
                                committedOffsetX = offsetX
                                committedOffsetY = offsetY
                                committedScale = scale
                                persist()
                            }
                            GestureKind.Undecided -> {
                                if (longPressFired) {
                                    // 已进入编辑，松手后保持编辑态
                                } else if (isEditingLatest) {
                                    if (pressCandidate == null) {
                                        isEditing = false
                                        draggingItemId = null
                                        dropTargetId = null
                                    }
                                } else if (pressCandidate != null) {
                                    lastBlankTapAt = 0L
                                    onSelectLatest(pressCandidate!!)
                                } else {
                                    val now = System.currentTimeMillis()
                                    if (lastBlankTapAt > 0 && now - lastBlankTapAt < 350) {
                                        lastBlankTapAt = 0L
                                        recenter()
                                    } else {
                                        lastBlankTapAt = now
                                    }
                                }
                            }
                        }
                    }
                },
        ) {
            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.Hexagon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.18f),
                        modifier =
                            Modifier
                                .size(48.dp)
                                .align(Alignment.Center)
                                .graphicsLayer { translationY = with(density) { -52.dp.toPx() } },
                    )
                    Text(
                        emptyHint,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 24.dp),
                    )
                }
            } else {
                items.forEachIndexed { index, item ->
                    val pos = positions.getOrElse(index) { HubHoneycombLayout.Point(0f, 0f) }
                    val isDragSource = draggingItemId == item.id
                    val focus =
                        HubHoneycombLayout.focusScale(
                            worldPosition = pos,
                            scale = scale,
                            offsetX = offsetX,
                            offsetY = offsetY,
                            viewport = HubHoneycombLayout.Size(w, h),
                            spacing = hexSpacing,
                        )
                    val sidePx = max(minIconSidePx, baseIconSidePx * scale * focus)
                    val blurPx =
                        if (isDragSource || reduceMotion) {
                            0f
                        } else {
                            HubHoneycombLayout.focusBlurRadius(focus, baseIconSidePx * scale)
                        }
                    val screenCenter =
                        Offset(
                            w * 0.5f + pos.x * scale + offsetX,
                            h * 0.5f + pos.y * scale + offsetY,
                        )
                    val drawCenter = if (isDragSource) dragFinger else screenCenter
                    val isDrop = dropTargetId == item.id && !isDragSource
                    val isAnimating = animatingItemId == item.id
                    val sideDp = with(density) { sidePx.toDp() }

                    Box(
                        modifier =
                            Modifier
                                .align(Alignment.TopStart)
                                .graphicsLayer {
                                    translationX = drawCenter.x - sidePx / 2f
                                    translationY = drawCenter.y - sidePx / 2f
                                    alpha = if (isDragSource) 0.92f else (0.28f + 0.72f * focus)
                                }
                                .size(sideDp)
                                .then(
                                    if (blurPx > 0.5f) {
                                        Modifier.blur(with(density) { blurPx.toDp() })
                                    } else {
                                        Modifier
                                    },
                                )
                                .scale(if (isAnimating) 1.12f else if (isDrop) 1.08f else 1f)
                                .rotate(if (isEditing && !isDragSource) jiggle else 0f)
                                .shadow(
                                    elevation = if (isDragSource) 10.dp else (sideDp.value * 0.08f * focus).dp,
                                    shape = CircleShape,
                                ),
                        contentAlignment = Alignment.Center,
                    ) {
                        HubHoneycombRoundIcon(item = item, side = sideDp)
                    }
                }
            }

            AnimatedVisibility(
                visible = isEditing,
                enter = fadeIn() + slideInVertically(),
                exit = fadeOut() + slideOutVertically(),
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 10.dp),
            ) {
                Surface(shape = CircleShape, tonalElevation = 2.dp) {
                    TextButton(
                        onClick = {
                            isEditing = false
                            draggingItemId = null
                            dropTargetId = null
                        },
                    ) {
                        Text(editDoneLabel)
                    }
                }
            }
        }
    }
}

@Composable
fun HubHoneycombRoundIcon(
    item: HubLauncherItem,
    side: Dp,
) {
    val slot = item.slot
    val inset = side * 0.06f
    Box(
        modifier =
            Modifier
                .size(side)
                .shadow(2.dp, CircleShape)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(side - inset * 2)
                .clip(CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            when {
                slot.kind == "shortcut" -> {
                    val kind = slot.shortcutKind.orEmpty()
                    if (kind == "openURL") {
                        val bytes = remember(slot.iconPNG) { slot.iconPngBytes() }
                        val bmp =
                            remember(bytes) {
                                bytes?.let {
                                    if (it.size < 32) return@let null
                                    android.graphics.BitmapFactory
                                        .decodeByteArray(it, 0, it.size)
                                        ?.asImageBitmap()
                                }
                            }
                        if (bmp != null) {
                            Image(bmp, null, Modifier.fillMaxSize())
                        } else {
                            ShortcutGlyph(kind)
                        }
                    } else {
                        ShortcutGlyph(kind)
                    }
                }
                else -> {
                    val bytes = remember(slot.iconPNG, slot.id) { slot.iconPngBytes() }
                    val bmp =
                        remember(bytes) {
                            bytes?.let {
                                if (it.size < 32) return@let null
                                android.graphics.BitmapFactory
                                    .decodeByteArray(it, 0, it.size)
                                    ?.asImageBitmap()
                            }
                        }
                    when {
                        bmp != null -> Image(bmp, null, Modifier.fillMaxSize())
                        slot.isEmpty ->
                            Icon(
                                Icons.Default.Add,
                                null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        else ->
                            Icon(
                                Icons.Default.Apps,
                                null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                    }
                }
            }
        }
    }
}

@Composable
private fun ShortcutGlyph(kind: String) {
    val icon =
        when (kind) {
            "volume" -> Icons.Default.VolumeUp
            "brightness" -> Icons.Default.WbSunny
            "mediaTransport" -> Icons.Default.Speed
            "screenshotFull", "screenshotSelection" -> Icons.Default.PhotoCamera
            "selectAll" -> Icons.Default.SelectAll
            "copy" -> Icons.Default.ContentCopy
            "paste" -> Icons.Default.ContentPaste
            "openURL" -> Icons.Default.Link
            else -> Icons.Default.Apps
        }
    Icon(
        imageVector = icon,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.fillMaxSize(0.55f),
    )
}
