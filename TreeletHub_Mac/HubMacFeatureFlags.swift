import Foundation

/// Mac 敏感能力开关。真正的分发差异在编译条件 `APP_STORE`（见 `HubDistribution`）。
///
/// 日常开发 / DMG：scheme `TreeletHub_Mac`
/// App Store 审核包：scheme `TreeletHub_Mac_AppStore`
enum HubMacFeatureFlags {
    /// 键盘启动器（需 Input Monitoring + Accessibility）。
    /// App Store 包为 false，且权限 API 会在编译期剔除。
    static var allowsGlobalInputMonitoring: Bool {
        HubDistribution.includesKeyboardLauncher
    }
}
