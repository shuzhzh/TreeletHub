import Foundation

/// 对外分发链接（官网文案 / iOS 冷启动「复制链接」共用）。
/// Mac 直装走 Cloudflare 自定义域名 `models.appda.store`（国内可达），不要用 GitHub / treelet.us。
enum HubDownloadURLs {
    /// Mac `.dmg`（R2 → treelet-model-cdn）。上传对象键保持 `treelethub/TreeletHub.dmg`。
    static let macDMG = URL(string: "https://models.appda.store/treelethub/TreeletHub.dmg")!

    /// 官网落地页（说明与配对引导；treelet.us 本身不托管安装包）。
    static let productPage = URL(string: "https://treelet.us/treelethub/")!

    /// 官网下载锚点。
    static let productPageMacDownload = URL(string: "https://treelet.us/treelethub/#download-mac")!

    /// iPhone / iPad App Store。
    static let iosAppStore = URL(
        string: "https://apps.apple.com/app/treelethub-%E6%95%88%E7%8E%87-%E6%8E%A7%E5%88%B6%E5%8F%B0/id6762348247"
    )!
}
