import CoreGraphics
import Foundation

/// 蜂巢螺旋坐标与 Watch App View 风格的视口缩放参数。
public enum HubHoneycombLayout {
    public static let defaultBaseIconSide: CGFloat = 72
    public static let defaultMinScale: CGFloat = 0.35
    public static let defaultMaxScale: CGFloat = 3.2
    /// 首次进入 / 双击复位时的缩放（略大于 1，中心图标更醒目）。
    public static let defaultScale: CGFloat = 1.4
    /// 布局算法版本：变更后清掉旧视口持久化（避免旧空心螺旋的偏移残留）。
    public static let layoutRevision = 3

    /// 相邻图标中心距（相对基础边长）。
    public static func spacing(forBaseIconSide side: CGFloat) -> CGFloat {
        side * 1.08
    }

    /// 轴向六边形螺旋：中心 → 外环。
    public static func spiralPositions(count: Int, spacing: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        var axial: [(q: Int, r: Int)] = [(0, 0)]
        if count == 1 {
            return [axialToCartesian(q: 0, r: 0, spacing: spacing)]
        }
        // 与 Red Blob / Apple Watch 一致：每环从 directions[4]*ring 起步，再沿 6 边绕满。
        // 旧起点 (0,-ring) 与该方向序不匹配，会导致 ring-1 永久缺格、整体偏斜成空心环。
        let directions = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
        var ring = 1
        while axial.count < count {
            var q = directions[4].0 * ring
            var r = directions[4].1 * ring
            for dir in 0..<6 {
                for _ in 0..<ring {
                    axial.append((q, r))
                    if axial.count >= count { break }
                    q += directions[dir].0
                    r += directions[dir].1
                }
                if axial.count >= count { break }
            }
            ring += 1
        }
        return axial.prefix(count).map { axialToCartesian(q: $0.q, r: $0.r, spacing: spacing) }
    }

    public static func axialToCartesian(q: Int, r: Int, spacing: CGFloat) -> CGPoint {
        let x = spacing * (CGFloat(q) + CGFloat(r) * 0.5)
        let y = spacing * (CGFloat(r) * 0.8660254037844386)
        return CGPoint(x: x, y: y)
    }

    public static func contentBounds(positions: [CGPoint], pad: CGFloat) -> CGRect {
        guard let first = positions.first else {
            return CGRect(x: -pad, y: -pad, width: pad * 2, height: pad * 2)
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for p in positions.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(
            x: minX - pad,
            y: minY - pad,
            width: max(maxX - minX + pad * 2, pad * 2),
            height: max(maxY - minY + pad * 2, pad * 2)
        )
    }

    /// 距焦点越远越小（Watch 鱼眼）。按图标间距归一化，大屏也不会“几乎看不出落差”。
    public static func focusScale(
        worldPosition: CGPoint,
        scale: CGFloat,
        offset: CGSize,
        viewport: CGSize,
        spacing: CGFloat,
        strength: CGFloat = 0.78
    ) -> CGFloat {
        guard viewport.width > 1, viewport.height > 1, scale > 0.001 else { return 1 }
        let focusWorld = CGPoint(x: -offset.width / scale, y: -offset.height / scale)
        let dist = hypot(worldPosition.x - focusWorld.x, worldPosition.y - focusWorld.y)
        // 约 2.2 环外落到最弱；与视口对角线脱钩，Mac / Watch 观感一致。
        let maxDist = max(spacing * 2.2, 1)
        let t = min(1, dist / maxDist)
        let curved = t * t * (3 - 2 * t)
        return 1 - strength * curved
    }

    /// 周边图标轻微高斯模糊（焦点处为 0）。
    public static func focusBlurRadius(focus: CGFloat, baseIconSide: CGFloat) -> CGFloat {
        let falloff = max(0, min(1, 1 - focus))
        // 只做轻微虚化，避免外围糊成一团。
        return falloff * falloff * baseIconSide * 0.045
    }

    /// 默认视口偏移：中心格对齐视口光学中心（略偏上，贴近 Watch 观感）。
    public static func defaultOffset(viewport: CGSize) -> CGSize {
        guard viewport.height > 1 else { return .zero }
        return CGSize(width: 0, height: -viewport.height * 0.045)
    }
}
