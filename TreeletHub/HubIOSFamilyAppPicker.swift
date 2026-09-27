#if os(iOS)
import Foundation

/// 一次「添加应用」的结果。只接受带 bundle id 的目录 / App Store 条目，才能显示官方图标并启动。
struct HubIOSFamilyAppPick: Identifiable {
    let bundleIdentifier: String?
    let displayName: String?
    let tokenData: Data?
    let iconPNG: Data?
    var launchURLString: String? = nil

    var id: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return "b:\(bundleIdentifier)" }
        return "t:\(tokenData?.base64EncodedString() ?? "")"
    }
}
#endif
