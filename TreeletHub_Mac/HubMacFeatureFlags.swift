import Foundation

/// Feature switches for Mac capabilities that touch sensitive TCC permissions.
enum HubMacFeatureFlags {
    /// 键盘启动器（需 Input Monitoring + Accessibility）。
    /// 与 AI 控制板无关；AI 控制已改为 Codex 深链接 / CLI，不再键注入。
    /// 打字音效暂不开放。
    static let allowsGlobalInputMonitoring = true
}
