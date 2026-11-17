import Foundation

/// Mac 双分发入口。
///
/// - 官网 / GitHub：scheme `TreeletHub_Mac`，configuration `Debug` / `Release`（全功能）
/// - Mac App Store：scheme `TreeletHub_Mac_AppStore`，configuration `AppStore`（合规裁剪）
public enum HubDistribution {
    /// 仅 Mac App Store 合规包为 `true`。
    public static var isAppStoreMacBuild: Bool {
        #if os(macOS) && APP_STORE
        true
        #else
        false
        #endif
    }

    /// 键盘启动器（输入监控 + 辅助功能）只出现在官网 / GitHub Direct 包。
    public static var includesKeyboardLauncher: Bool {
        #if os(macOS)
        !isAppStoreMacBuild
        #else
        true
        #endif
    }

    /// 手机键鼠注入只出现在官网 Direct 包（TreeletHub Pro）。Mac App Store 构建为 false。
    public static var includesRemoteInput: Bool {
        #if os(macOS)
        !isAppStoreMacBuild
        #else
        false
        #endif
    }
}
