import AppKit
import Foundation

/// 灵动岛尺寸偏好：未设置时用按屏宽/屏高推算的默认值；用户拖拽调整后写入 UserDefaults，之后始终按自定义值显示（仍受当前屏幕上下限夹紧）。
@MainActor
enum HubIslandSizePreferences {
    static let expandedWidthKey = "treelethub.island.size.expandedWidth"
    static let expandedBodyHeightKey = "treelethub.island.size.expandedBodyHeight"
    static let collapsedWidthKey = "treelethub.island.size.collapsedWidth"
    static let collapsedBodyHeightKey = "treelethub.island.size.collapsedBodyHeight"

    static var expandedWidth: CGFloat? {
        get { stored(expandedWidthKey) }
        set { write(expandedWidthKey, newValue) }
    }

    static var expandedBodyHeight: CGFloat? {
        get { stored(expandedBodyHeightKey) }
        set { write(expandedBodyHeightKey, newValue) }
    }

    static var collapsedWidth: CGFloat? {
        get { stored(collapsedWidthKey) }
        set { write(collapsedWidthKey, newValue) }
    }

    static var collapsedBodyHeight: CGFloat? {
        get { stored(collapsedBodyHeightKey) }
        set { write(collapsedBodyHeightKey, newValue) }
    }

    static var hasAnyCustomSize: Bool {
        expandedWidth != nil
            || expandedBodyHeight != nil
            || collapsedWidth != nil
            || collapsedBodyHeight != nil
    }

    static func resetAll() {
        let d = UserDefaults.standard
        d.removeObject(forKey: expandedWidthKey)
        d.removeObject(forKey: expandedBodyHeightKey)
        d.removeObject(forKey: collapsedWidthKey)
        d.removeObject(forKey: collapsedBodyHeightKey)
    }

    private static func stored(_ key: String) -> CGFloat? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let v = UserDefaults.standard.double(forKey: key)
        guard v.isFinite, v > 0 else { return nil }
        return CGFloat(v)
    }

    private static func write(_ key: String, _ value: CGFloat?) {
        if let value, value.isFinite, value > 0 {
            UserDefaults.standard.set(Double(value), forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// 拖拽调整时使用的边缘。
enum HubIslandResizeEdge: Equatable {
    case leading
    case trailing
    case bottom
    case bottomTrailing
}
