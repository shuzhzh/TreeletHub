package com.treelet.treelethub.hub

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** 蜂巢螺旋坐标与 Watch App View 风格的视口缩放参数（对齐 iOS HubHoneycombLayout）。 */
object HubHoneycombLayout {
    const val defaultBaseIconSide = 72f
    const val defaultMinScale = 0.35f
    const val defaultMaxScale = 3.2f
    const val defaultScale = 1.4f
    /** 布局算法版本：变更后清掉旧视口持久化（避免旧空心螺旋 / 错误密度换算的偏移残留）。 */
    const val layoutRevision = 4

    fun spacing(forBaseIconSide: Float): Float = forBaseIconSide * 1.08f

    data class Point(val x: Float, val y: Float)

    data class Rect(
        val x: Float,
        val y: Float,
        val width: Float,
        val height: Float,
    )

    data class Size(val width: Float, val height: Float)

    fun spiralPositions(count: Int, spacing: Float): List<Point> {
        if (count <= 0) return emptyList()
        val axial = mutableListOf(0 to 0)
        if (count == 1) {
            return listOf(axialToCartesian(0, 0, spacing))
        }
        val directions =
            listOf(
                1 to 0,
                1 to -1,
                0 to -1,
                -1 to 0,
                -1 to 1,
                0 to 1,
            )
        var ring = 1
        while (axial.size < count) {
            var q = directions[4].first * ring
            var r = directions[4].second * ring
            for (dir in 0 until 6) {
                repeat(ring) {
                    axial.add(q to r)
                    if (axial.size >= count) return@repeat
                    q += directions[dir].first
                    r += directions[dir].second
                }
                if (axial.size >= count) break
            }
            ring++
        }
        return axial.take(count).map { (q, r) -> axialToCartesian(q, r, spacing) }
    }

    fun axialToCartesian(q: Int, r: Int, spacing: Float): Point {
        val x = spacing * (q + r * 0.5f)
        val y = spacing * (r * 0.8660254037844386f)
        return Point(x, y)
    }

    fun contentBounds(positions: List<Point>, pad: Float): Rect {
        val first = positions.firstOrNull()
            ?: return Rect(-pad, -pad, pad * 2, pad * 2)
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for (p in positions.drop(1)) {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return Rect(
            x = minX - pad,
            y = minY - pad,
            width = max(maxX - minX + pad * 2, pad * 2),
            height = max(maxY - minY + pad * 2, pad * 2),
        )
    }

    fun focusScale(
        worldPosition: Point,
        scale: Float,
        offsetX: Float,
        offsetY: Float,
        viewport: Size,
        spacing: Float,
        strength: Float = 0.78f,
    ): Float {
        if (viewport.width <= 1f || viewport.height <= 1f || scale <= 0.001f) return 1f
        val focusWorld = Point(-offsetX / scale, -offsetY / scale)
        val dist = hypot(worldPosition.x - focusWorld.x, worldPosition.y - focusWorld.y)
        val maxDist = max(spacing * 2.2f, 1f)
        val t = min(1f, dist / maxDist)
        val curved = t * t * (3 - 2 * t)
        return 1f - strength * curved
    }

    fun focusBlurRadius(focus: Float, baseIconSide: Float): Float {
        val falloff = max(0f, min(1f, 1f - focus))
        return falloff * falloff * baseIconSide * 0.045f
    }

    fun defaultOffsetY(viewportHeight: Float): Float {
        if (viewportHeight <= 1f) return 0f
        return -viewportHeight * 0.045f
    }
}
