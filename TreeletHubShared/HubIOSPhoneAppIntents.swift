#if os(iOS)
import AppIntents
import Foundation
import WidgetKit

// 说明：WidgetKit 小组件里不存在捏合 / 拖动手势，只有按钮（App Intent）与 Link 可交互。
// 因此「放大缩小 / 滑动」在小组件里以按钮步进实现；主应用里的捏合 / 拖动结果会同步进来作为默认视口。
// 点按图标优先走目标 App 自己的 URL Scheme（`OpenURLIntent` / `Link`）。
// 没有可用 scheme 时用 `LaunchInstalledPhoneAppIntent`，并且 `openAppWhenRun = false`，避免打开 TreeletHub。

/// 小组件「上一组 / 下一组」：把蜂巢焦点转到相邻应用（滑动的按钮替代）。
public struct RotatePhoneHoneycombIntent: AppIntent {
    public static var title: LocalizedStringResource = "Rotate Phone Honeycomb"
    public static var openAppWhenRun = false
    public static var isDiscoverable = false

    @Parameter(title: "Delta")
    public var delta: Int

    public init() {
        delta = 1
    }

    public init(delta: Int) {
        self.delta = delta
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        HubIOSAppGroup.rotateWidget(by: delta)
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
        return .result()
    }
}

/// 小组件缩放步进（捏合手势的按钮替代）。
public struct ZoomPhoneHoneycombIntent: AppIntent {
    public static var title: LocalizedStringResource = "Zoom Phone Honeycomb"
    public static var openAppWhenRun = false
    public static var isDiscoverable = false

    @Parameter(title: "Factor")
    public var factor: Double

    public init() {
        factor = 1.2
    }

    public init(factor: Double) {
        self.factor = factor
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let next = HubIOSAppGroup.widgetScale() * CGFloat(factor)
        HubIOSAppGroup.setWidgetViewport(
            scale: next,
            normalizedOffset: HubIOSAppGroup.widgetNormalizedOffset()
        )
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
        return .result()
    }
}

/// 小组件复位：回到默认缩放与居中。
public struct ResetPhoneHoneycombViewportIntent: AppIntent {
    public static var title: LocalizedStringResource = "Reset Phone Honeycomb"
    public static var openAppWhenRun = false
    public static var isDiscoverable = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        HubIOSAppGroup.resetWidgetViewport()
        HubIOSAppGroup.setWidgetRotationIndex(0)
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
        return .result()
    }
}

/// 小组件上没有公开 URL Scheme 的系统 App（相机、设置、指南针等）。
/// 必须 `openAppWhenRun = false`，否则一点击就进入 TreeletHub。
public struct LaunchInstalledPhoneAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Launch Installed App"
    public static var openAppWhenRun = false
    public static var isDiscoverable = false

    @Parameter(title: "Bundle Identifier")
    public var bundleIdentifier: String

    public init() {
        bundleIdentifier = ""
    }

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("slot.") else {
            return .result()
        }
        _ = await HubIOSInstalledApps.openAwaiting(bundleIdentifier: bundleIdentifier)
        return .result()
    }
}
#endif
