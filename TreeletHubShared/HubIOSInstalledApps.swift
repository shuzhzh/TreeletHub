#if os(iOS)
import Foundation
import ObjectiveC
import UIKit

/// 公开 API 启动器：只能打开登记了 URL Scheme 的应用，图标走 App Store artwork。
/// 不枚举本机已安装列表，也不调用 LaunchServices / SpringBoard。
nonisolated public enum HubIOSInstalledApps {
    public struct Record: Identifiable, Hashable, Sendable {
        public let bundleIdentifier: String
        public let displayName: String
        public var id: String { bundleIdentifier }
    }

    private static let skipBundleIds: Set<String> = [
        "com.apple.springboard",
        "com.apple.Spotlight",
        "com.apple.Search.Framework",
        "com.treelet.TreeletHub",
        "com.treelet.TreeletHub.PhoneWidget",
        "com.treelet.TreeletHubPhoneWidget",
        "com.apple.Preferences",
    ]

    public static var canQueryInstallation: Bool { false }

    /// 目录里登记了公开 URL、因此能启动的应用。相机走系统拍照界面；电话改为选联系人后一键呼叫。
    public static func canLaunch(_ bundleIdentifier: String) -> Bool {
        needsSystemCamera(bundleIdentifier)
            || needsContactCallSetup(bundleIdentifier)
            || isContactCall(bundleIdentifier)
            || directLaunchURL(for: bundleIdentifier) != nil
    }

    /// iOS 没有公开 URL 打开「相机」App，用系统拍照界面代替。
    public static func needsSystemCamera(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.apple.camera"
    }

    /// 目录里的「电话」：不能空号拉起电话 App，只能用来添加呼叫联系人。
    public static func needsContactCallSetup(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.apple.mobilephone"
    }

    public static func isContactCall(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier.hasPrefix("contact.tel.")
    }

    public static func installedApps() -> [Record] {
        launchableCatalogApps()
    }

    /// 添加页「常用应用」：只列能公开打开的热门应用。
    public static func suggestedLauncherApps() -> [Record] {
        suggestedBundleIds.compactMap { bundleId in
            guard canLaunch(bundleId),
                  isLauncherCandidate(bundleIdentifier: bundleId, displayName: nil)
            else { return nil }
            return Record(
                bundleIdentifier: bundleId,
                displayName: resolvedName(bundleId: bundleId, preferred: nil)
            )
        }
    }

    /// 目录里其余可打开的应用（不含常用墙）。
    public static func locallyEnumeratedApps() -> [Record] {
        let suggested = Set(suggestedBundleIds)
        return launchableCatalogApps().filter { !suggested.contains($0.bundleIdentifier) }
    }

    private static func launchableCatalogApps() -> [Record] {
        var seen = Set<String>()
        var result: [Record] = []
        for candidate in probeCatalog {
            guard !needsContactCallSetup(candidate.bundleId),
                  canLaunch(candidate.bundleId),
                  isLauncherCandidate(bundleIdentifier: candidate.bundleId, displayName: candidate.name),
                  seen.insert(candidate.bundleId).inserted
            else { continue }
            result.append(
                Record(
                    bundleIdentifier: candidate.bundleId,
                    displayName: resolvedName(bundleId: candidate.bundleId, preferred: candidate.name)
                )
            )
        }
        return dedupedByDisplayName(result).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public static let suggestedBundleIds: [String] = [
        "com.tencent.xin",
        "com.alipay.iphoneclient",
        "com.ss.iphone.ugc.Aweme",
        "com.xingin.discover",
        "com.taobao.taobao4iphone",
        "com.meituan.imeituan",
        "com.xunmeng.pinduoduo",
        "com.tencent.mqq",
        "com.laiwang.DingTalk",
        "tv.danmaku.bilianime",
        "com.netease.cloudmusic",
        "com.autonavi.amap",
        "com.360buy.jdmobile",
        "com.sina.weibo",
        "com.apple.mobilesafari",
        "com.apple.MobileSMS",
        "com.apple.camera",
        "com.apple.mobileslideshow",
        "com.apple.mobilephone",
        "com.apple.Maps",
        "com.apple.Music",
        "com.apple.AppStore",
        "com.apple.mobilenotes",
        "com.apple.mobilecal",
        "com.apple.mobiletimer",
        "net.whatsapp.WhatsApp",
        "com.burbn.instagram",
        "ph.telegra.Telegraph",
        "com.google.ios.youtube",
        "com.google.chrome.ios",
        "com.spotify.client",
        "com.zhiliaoapp.musically",
        "com.google.Gmail",
        "com.facebook.Facebook",
        "com.openai.chat",
        "com.bot.doubao",
        "com.anthropic.claude",
        "com.deepseek.chat",
        "com.google.gemini",
        "com.moonshot.kimichat",
        "com.tencent.hunyuan.app.chat",
    ]

    /// 把能直接打开的 URL 记到 App Group。只写已知 scheme，不扫 LaunchServices。
    public static func rememberLaunchURL(for bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("slot.") else { return }
        if needsContactCallSetup(bundleIdentifier) { return }
        if let url = directLaunchURL(for: bundleIdentifier) {
            HubIOSAppGroup.saveLaunchURL(url.absoluteString, for: bundleIdentifier)
        }
    }

    /// 同一应用常有多个 bundle id（微信 / 微信手表版）。列表里按显示名只留第一条。
    private static func dedupedByDisplayName(_ records: [Record]) -> [Record] {
        var seen = Set<String>()
        var kept: [Record] = []
        for record in records {
            let key = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            kept.append(record)
        }
        return kept
    }

    /// `nil` 表示无法判断（不要因此清掉用户列表）。
    /// 公开 API 无法可靠探测安装状态，有可打开 URL 的条目一律保留。
    public static func isInstalled(_ bundleIdentifier: String) -> Bool? {
        guard !bundleIdentifier.isEmpty else { return false }
        return nil
    }

    public static func displayName(for bundleIdentifier: String) -> String? {
        resolvedName(bundleId: bundleIdentifier, preferred: nil)
    }

    public static func bundleIdentifier(matchingDisplayName name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let catalogId = catalogBundleIdentifier(matching: trimmed) {
            return catalogId
        }
        let apps = installedApps()
        if let exact = apps.first(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.bundleIdentifier
        }
        // 模糊匹配只接受「唯一」命中，否则会把 A 应用的名字对到 B 应用的 bundle id，进而显示错误图标。
        guard trimmed.count >= 2 else { return nil }
        let fuzzy = apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || trimmed.localizedCaseInsensitiveContains($0.displayName)
        }
        return fuzzy.count == 1 ? fuzzy[0].bundleIdentifier : nil
    }

    /// 目录中英 / 中文名反查，不依赖本机枚举是否完整。
    private static func catalogBundleIdentifier(matching name: String) -> String? {
        if let zh = zhHansNames.first(where: { $0.value.caseInsensitiveCompare(name) == .orderedSame }) {
            return zh.key
        }
        let english = probeCatalog.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if english.count == 1 { return english[0].bundleId }
        return nil
    }

    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// 同步可得的图标：只读已缓存的 App Store artwork。
    public static func iconImage(
        for bundleIdentifier: String,
        allowLaunchServicesForThirdParty: Bool = false
    ) -> UIImage? {
        _ = allowLaunchServicesForThirdParty
        return HubIOSAppStoreArtwork.cachedImage(for: bundleIdentifier)
    }

    /// 异步取图：只走 App Store 官方 artwork。
    public static func iconImageIncludingStore(
        for bundleIdentifier: String,
        displayName: String? = nil
    ) async -> UIImage? {
        await Task.detached(priority: .utility) {
            if let cached = HubIOSAppStoreArtwork.cachedImageCheap(for: bundleIdentifier) {
                return cached
            }
            if let store = await HubIOSAppStoreArtwork.image(for: bundleIdentifier, displayName: displayName) {
                return store
            }
            return HubIOSAppSymbol.fallbackIcon(for: bundleIdentifier)
        }.value
    }

    public static func iconPNG(for bundleIdentifier: String, maxPixelSide: CGFloat = 512) -> Data? {
        guard let image = iconImage(for: bundleIdentifier) else { return nil }
        return image.hub_pngData(maxPixelSide: maxPixelSide)
    }

    @discardableResult
    public static func open(bundleIdentifier: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("slot.") else {
            completion?(false)
            return false
        }

        // 必须跳出当前触摸手势再 open，否则系统常会静默丢弃。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            attemptLaunch(bundleIdentifier: bundleIdentifier, completion: completion)
        }
        return true
    }

    /// 小组件 Intent 在扩展进程里调用：等到 URL 或系统启动接口给出结果。
    public static func openAwaiting(bundleIdentifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            let finish: (Bool) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            let started = open(bundleIdentifier: bundleIdentifier) { success in
                finish(success)
            }
            if !started {
                finish(false)
            }
        }
    }

    /// 公开目录里登记过的 scheme。联系人呼叫优先用已保存的 `tel:` 号码。
    public static func directLaunchURL(for bundleIdentifier: String) -> URL? {
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("slot.") else { return nil }
        if let saved = HubIOSAppGroup.loadLaunchURL(for: bundleIdentifier),
           let url = URL(string: saved),
           !isSelfURL(url),
           isUsableLaunchURL(url) {
            return url
        }
        if needsContactCallSetup(bundleIdentifier) { return nil }
        if let url = knownURL(for: bundleIdentifier), !isSelfURL(url), isUsableLaunchURL(url) {
            return url
        }
        return alternateKnownURLs(for: bundleIdentifier).first(where: { !isSelfURL($0) && isUsableLaunchURL($0) })
    }

    private static func isUsableLaunchURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "tel" || scheme == "telprompt" {
            let body = url.absoluteString.drop { $0 != ":" }.dropFirst()
            return body.filter(\.isNumber).count >= 3
        }
        if scheme == "app-prefs" || scheme == "prefs" || scheme.hasPrefix("prefs") {
            return false
        }
        return true
    }

    private static func isSelfURL(_ url: URL) -> Bool {
        (url.scheme?.lowercased() ?? "") == "treelethub"
    }

    private static func attemptLaunch(
        bundleIdentifier: String,
        completion: ((Bool) -> Void)?
    ) {
        if needsSystemCamera(bundleIdentifier) {
            completion?(false)
            return
        }
        let urls = launchURLs(for: bundleIdentifier)
        guard !urls.isEmpty else {
            completion?(false)
            return
        }
        openURLChain(urls, completion: completion ?? { _ in })
    }

    private static func launchURLs(for bundleIdentifier: String) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        func append(_ url: URL?) {
            guard let url, !isSelfURL(url) else { return }
            let key = url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }
        append(directLaunchURL(for: bundleIdentifier))
        append(knownURL(for: bundleIdentifier))
        for extra in alternateKnownURLs(for: bundleIdentifier) {
            append(extra)
        }
        return urls
    }

    private static func openURLChain(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        guard let url = urls.first else {
            completion(false)
            return
        }
        openURL(url) { success in
            if success {
                completion(true)
                return
            }
            openURLChain(Array(urls.dropFirst()), completion: completion)
        }
    }

    /// 小组件 / 外部通过 `treelethub://` 深链进入主应用时的动作。
    public enum IncomingAction: Equatable, Sendable {
        /// 启动指定 bundle id 的应用（小组件点按）。
        case launchApp(bundleIdentifier: String)
        /// 仅切到「手机」页。
        case showPhoneTab
    }

    public static func incomingAction(from url: URL) -> IncomingAction? {
        guard url.scheme?.lowercased() == "treelethub" else { return nil }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        if host == "phone" || path == "/phone" {
            return .showPhoneTab
        }
        guard host == "launch-phone-app" || path == "/launch-phone-app" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        if let bundleId = items?.first(where: { $0.name == "bundle" })?.value,
           !bundleId.isEmpty, !bundleId.hasPrefix("slot.") {
            return .launchApp(bundleIdentifier: bundleId)
        }
        if let name = items?.first(where: { $0.name == "name" })?.value,
           let bundleId = bundleIdentifier(matchingDisplayName: name),
           !bundleId.isEmpty {
            return .launchApp(bundleIdentifier: bundleId)
        }
        return .showPhoneTab
    }

    public static func openFromIncomingURL(_ url: URL) -> Bool {
        guard case .launchApp(let bundleId) = incomingAction(from: url) else { return false }
        return open(bundleIdentifier: bundleId)
    }

    /// 小组件里给每个图标用的深链：由主应用接管后再真正启动目标应用。
    public static func launchURL(for bundleIdentifier: String) -> URL? {
        var components = URLComponents()
        components.scheme = "treelethub"
        components.host = "launch-phone-app"
        components.queryItems = [URLQueryItem(name: "bundle", value: bundleIdentifier)]
        return components.url
    }

    public static var phoneTabURL: URL {
        URL(string: "treelethub://phone")!
    }

    private static func resolvedName(bundleId: String, preferred: String?) -> String {
        if isUsableDisplayName(preferred) { return preferred!.trimmingCharacters(in: .whitespacesAndNewlines) }
        return catalogName(for: bundleId) ?? fallbackName(bundleId)
    }

    private static func isUsableDisplayName(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        let folded = trimmed.lowercased()
        if folded == "(no path)" || folded == "no path" { return false }
        if folded == "(null)" || folded == "<null>" || folded == "null" { return false }
        if trimmed.hasPrefix("com.") && trimmed.contains(".") { return false }
        if trimmed.hasPrefix("/") { return false }
        if looksLikeWebsite(trimmed) { return false }
        return true
    }

    public static func looksLikeWebsite(_ raw: String?) -> Bool {
        let folded = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !folded.isEmpty else { return false }
        if folded.hasPrefix("http://") || folded.hasPrefix("https://") || folded.hasPrefix("www.") {
            return true
        }
        if folded.contains(" ") || folded.contains("/") { return false }
        let host = folded.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let parts = host.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, (2...24).contains(tld.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return tld.allSatisfy(\.isLetter)
    }

    /// 注意：bundle id 本身（com.apple.Preferences）在形态上就像域名，绝不能拿它做「是否网址」判断；
    /// 只有拿不到 bundle id 的条目（Family Controls 里混入的网站）才按显示名判断。
    public static func isLauncherCandidate(bundleIdentifier: String?, displayName: String?) -> Bool {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return shouldInclude(bundleId: bundleIdentifier)
        }
        return !looksLikeWebsite(displayName)
    }

    private static var prefersChinese: Bool {
        let stored = UserDefaults.standard.string(forKey: "treelethub.ios.uiLocaleIdentifier")
        if let stored { return stored.hasPrefix("zh") }
        if let first = Locale.preferredLanguages.first { return first.hasPrefix("zh") }
        return Locale.current.identifier.hasPrefix("zh")
    }

    private static func catalogName(for bundleId: String) -> String? {
        if prefersChinese, let zh = zhHansNames[bundleId] { return zh }
        return probeCatalog.first { $0.bundleId == bundleId }?.name
    }

    /// 系统枚举会带出大量非用户可见的 Apple 组件（认证对话框、Widget 渲染器、内部 Angel 进程等），
    /// 因此 `com.apple.*` 只保留已知的用户应用。
    private static let appleUserApps: Set<String> = {
        var set = Set(probeCatalog.map(\.bundleId).filter { $0.hasPrefix("com.apple.") })
        set.formUnion([
            "com.apple.stocks",
            "com.apple.Magnifier",
            "com.apple.Playgrounds",
            "com.apple.TestFlight",
            "com.apple.store.Jolly",
            "com.apple.mobileslideshow",
            "com.apple.Fitness",
            "com.apple.Home",
        ])
        return set
    }()

    private static func shouldInclude(bundleId: String) -> Bool {
        if skipBundleIds.contains(bundleId) { return false }
        if bundleId.hasPrefix("com.apple."), !appleUserApps.contains(bundleId) { return false }
        if bundleId.hasSuffix(".appex") { return false }
        if bundleId.contains(".watchkitapp") { return false }
        if bundleId.contains("com.apple.webapp") { return false }
        if bundleId.lowercased().contains("webclip") { return false }
        if bundleId.lowercased().contains("webapp") { return false }
        if bundleId.hasPrefix("com.apple.Posters") { return false }
        if bundleId.hasPrefix("com.apple.NanoUniverse") { return false }
        if bundleId.contains("Poster") { return false }
        if bundleId.hasSuffix("Service") { return false }
        if bundleId.contains("LoginUI") { return false }
        if bundleId.contains("PreviewShell") { return false }
        if bundleId.contains("datadetectors") { return false }
        if bundleId.contains("ActivityProgress") { return false }
        if bundleId.contains("MediaRemoteUI") { return false }
        return true
    }

    private static func fallbackName(_ bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }

    /// 有公开 URL Scheme 的常见应用目录。
    private static let probeCatalog: [(bundleId: String, name: String)] = [
        ("com.apple.mobilephone", "Phone"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.apple.mobilesafari", "Safari"),
        ("com.apple.camera", "Camera"),
        ("com.apple.mobileslideshow", "Photos"),
        ("com.apple.mobilemail", "Mail"),
        ("com.apple.Maps", "Maps"),
        ("com.apple.Music", "Music"),
        ("com.apple.mobilecal", "Calendar"),
        ("com.apple.mobilenotes", "Notes"),
        ("com.apple.AppStore", "App Store"),
        ("com.apple.weather", "Weather"),
        ("com.apple.mobiletimer", "Clock"),
        ("com.apple.facetime", "FaceTime"),
        ("com.apple.DocumentsApp", "Files"),
        ("com.apple.Passbook", "Wallet"),
        ("com.apple.MobileAddressBook", "Contacts"),
        ("com.apple.Health", "Health"),
        ("com.apple.shortcuts", "Shortcuts"),
        ("com.apple.reminders", "Reminders"),
        ("com.apple.news", "News"),
        ("com.apple.Fitness", "Fitness"),
        ("com.apple.Bridge", "Watch"),
        ("com.apple.Home", "Home"),
        ("com.apple.Translate", "Translate"),
        ("com.apple.measure", "Measure"),
        ("com.apple.calculator", "Calculator"),
        ("com.apple.compass", "Compass"),
        ("com.apple.VoiceMemos", "Voice Memos"),
        ("com.apple.tips", "Tips"),
        ("com.apple.tv", "TV"),
        ("com.apple.podcasts", "Podcasts"),
        ("com.apple.iBooks", "Books"),
        ("com.apple.MobileStore", "iTunes Store"),
        ("com.apple.FindMy", "Find My"),
        ("com.apple.freeform", "Freeform"),
        ("com.apple.Journal", "Journal"),
        ("com.apple.Passwords", "Passwords"),
        ("com.apple.Preview", "Preview"),
        ("com.tencent.xin", "WeChat"),
        ("com.tencent.mqq", "QQ"),
        ("com.alipay.iphoneclient", "Alipay"),
        ("com.taobao.taobao4iphone", "Taobao"),
        ("com.laiwang.DingTalk", "DingTalk"),
        ("com.ss.iphone.ugc.Aweme", "Douyin"),
        ("com.xingin.discover", "Xiaohongshu"),
        ("tv.danmaku.bilianime", "Bilibili"),
        ("tv.danmaku.bilibilihd", "Bilibili"),
        ("com.bilibili.bilianime", "Bilibili"),
        ("com.netease.cloudmusic", "NetEase Music"),
        ("com.kugou.kugou1002", "Kugou"),
        ("com.tencent.QQMusic", "QQ Music"),
        ("com.baidu.BaiduMobile", "Baidu"),
        ("com.meituan.imeituan", "Meituan"),
        ("com.didi.kuaidi", "DiDi"),
        ("com.xiaojukeji.didi", "DiDi"),
        ("com.jingdong.app.mall", "JD"),
        ("com.360buy.jdmobile", "JD"),
        ("com.sina.weibo", "Weibo"),
        ("ph.telegra.Telegraph", "Telegram"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.burbn.instagram", "Instagram"),
        ("com.zhiliaoapp.musically", "TikTok"),
        ("com.google.chrome.ios", "Chrome"),
        ("com.google.Gmail", "Gmail"),
        ("com.google.Maps", "Google Maps"),
        ("com.spotify.client", "Spotify"),
        ("com.atebits.Tweetie2", "X"),
        ("com.facebook.Facebook", "Facebook"),
        ("com.toyopagroup.picaboo", "Snapchat"),
        ("com.microsoft.Office.Word", "Word"),
        ("com.microsoft.Office.Excel", "Excel"),
        ("com.microsoft.Office.Outlook", "Outlook"),
        ("com.apple.mobilegarageband", "GarageBand"),
        ("com.apple.iMovie", "iMovie"),
        ("com.apple.Keynote", "Keynote"),
        ("com.apple.Pages", "Pages"),
        ("com.apple.Numbers", "Numbers"),
        ("com.apple.clips", "Clips"),
        ("com.tencent.ww", "WeCom"),
        ("com.tencent.xinWeChat", "WeChat"),
        ("com.tencent.tim", "TIM"),
        ("com.xunmeng.pinduoduo", "Pinduoduo"),
        ("com.taobao.fleamarket", "Xianyu"),
        ("com.taobao.tmall", "Tmall"),
        ("com.autonavi.minimap", "Amap"),
        ("com.autonavi.amap", "Amap"),
        ("com.baidu.BaiduMap", "Baidu Maps"),
        ("me.ele.ios.eleme", "Eleme"),
        ("com.eleme.eleme", "Eleme"),
        ("com.sankuai.meituan.takeoutnew", "Meituan Waimai"),
        ("com.zhihu.ios", "Zhihu"),
        ("com.ss.iphone.article.News", "Toutiao"),
        ("com.ss.iphone.ugc.live", "Douyin Lite"),
        ("com.tencent.mttlite", "QQ Browser"),
        ("com.quark.browser", "Quark"),
        ("com.apple.mobileme.fmf1", "Find My"),
        ("com.tencent.qqmail", "QQ Mail"),
        ("com.netease.news", "NetEase News"),
        ("com.youku.YouKu", "Youku"),
        ("com.qiyi.iphone", "iQiyi"),
        ("com.tencent.live4iphone", "Tencent Video"),
        ("com.kuaishou.nebula", "Kuaishou"),
        ("com.jiangjia.gif", "Kuaishou"),
        ("com.ximalaya.TingApple", "Ximalaya"),
        ("com.gemd.iting", "Ximalaya"),
        ("com.gotokeep.keep", "Keep"),
        ("com.dianping.dpscope", "Dianping"),
        ("ctrip.com", "Ctrip"),
        ("com.yixia.video", "Xiaoshipin"),
        ("com.sina.news", "Sina News"),
        ("com.tencent.xin.watch", "WeChat"),
        ("com.alipay.iphoneclient.AlipayWallet", "Alipay"),
        ("com.cainiao.cnwireless", "Cainiao"),
        ("com.apple.mobileipod", "Music"),
        ("com.google.ios.youtube", "YouTube"),
        ("com.google.Drive", "Google Drive"),
        ("net.whatsapp.WhatsAppSMB", "WhatsApp Business"),
        ("ph.telegra.Telegraph.Telegraph", "Telegram"),
        ("org.whispersystems.signal", "Signal"),
        ("com.hammerandchisel.discord", "Discord"),
        ("com.tinyspeck.chatlyio", "Slack"),
        ("us.zoom.videomeetings", "Zoom"),
        ("com.microsoft.skype.teams", "Teams"),
        ("notion.id", "Notion"),
        ("com.agilebits.onepassword7", "1Password"),
        ("com.lastpass.ilastpass", "LastPass"),
        ("com.burbn.barcelona", "Threads"),
        ("com.zhiliaoapp.musically.go", "TikTok Lite"),
        ("com.linkedin.LinkedIn", "LinkedIn"),
        ("com.atebits.Tweetie2", "X"),
        ("com.openai.chat", "ChatGPT"),
        ("com.bot.doubao", "Doubao"),
        ("com.anthropic.claude", "Claude"),
        ("com.deepseek.chat", "DeepSeek"),
        ("com.google.gemini", "Gemini"),
        ("com.moonshot.kimichat", "Kimi"),
        ("com.tencent.hunyuan.app.chat", "Yuanbao"),
        ("com.aliyun.ios.tongyi", "Qwen"),
    ]

    private static let zhHansNames: [String: String] = [
        "com.apple.mobilephone": "电话",
        "com.apple.MobileSMS": "信息",
        "com.apple.mobilesafari": "Safari",
        "com.apple.camera": "相机",
        "com.apple.mobileslideshow": "照片",
        "com.apple.mobilemail": "邮件",
        "com.apple.Maps": "地图",
        "com.apple.Music": "音乐",
        "com.apple.mobilecal": "日历",
        "com.apple.mobilenotes": "备忘录",
        "com.apple.AppStore": "App Store",
        "com.apple.weather": "天气",
        "com.apple.mobiletimer": "时钟",
        "com.apple.facetime": "FaceTime",
        "com.apple.DocumentsApp": "文件",
        "com.apple.Passbook": "钱包",
        "com.apple.MobileAddressBook": "通讯录",
        "com.apple.Health": "健康",
        "com.apple.shortcuts": "快捷指令",
        "com.apple.reminders": "提醒事项",
        "com.apple.news": "新闻",
        "com.apple.Fitness": "健身",
        "com.apple.Bridge": "Watch",
        "com.apple.Home": "家庭",
        "com.apple.Translate": "翻译",
        "com.apple.measure": "测量",
        "com.apple.calculator": "计算器",
        "com.apple.compass": "指南针",
        "com.apple.VoiceMemos": "语音备忘录",
        "com.apple.tips": "提示",
        "com.apple.tv": "TV",
        "com.apple.podcasts": "播客",
        "com.apple.iBooks": "图书",
        "com.apple.MobileStore": "iTunes Store",
        "com.apple.FindMy": "查找",
        "com.apple.freeform": "无边记",
        "com.apple.Journal": "日记",
        "com.apple.Passwords": "密码",
        "com.apple.Preview": "预览",
        "com.tencent.xin": "微信",
        "com.tencent.xinWeChat": "微信",
        "com.tencent.xin.watch": "微信",
        "com.alipay.iphoneclient.AlipayWallet": "支付宝",
        "com.tencent.mqq": "QQ",
        "com.alipay.iphoneclient": "支付宝",
        "com.taobao.taobao4iphone": "淘宝",
        "com.laiwang.DingTalk": "钉钉",
        "com.ss.iphone.ugc.Aweme": "抖音",
        "com.xingin.discover": "小红书",
        "tv.danmaku.bilianime": "哔哩哔哩",
        "tv.danmaku.bilibilihd": "哔哩哔哩",
        "com.bilibili.bilianime": "哔哩哔哩",
        "com.netease.cloudmusic": "网易云音乐",
        "com.kugou.kugou1002": "酷狗音乐",
        "com.tencent.QQMusic": "QQ音乐",
        "com.baidu.BaiduMobile": "百度",
        "com.meituan.imeituan": "美团",
        "com.didi.kuaidi": "滴滴出行",
        "com.xiaojukeji.didi": "滴滴出行",
        "com.jingdong.app.mall": "京东",
        "com.360buy.jdmobile": "京东",
        "com.sina.weibo": "微博",
        "ph.telegra.Telegraph": "Telegram",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.burbn.instagram": "Instagram",
        "com.zhiliaoapp.musically": "TikTok",
        "com.google.chrome.ios": "Chrome",
        "com.google.Gmail": "Gmail",
        "com.google.Maps": "Google 地图",
        "com.spotify.client": "Spotify",
        "com.atebits.Tweetie2": "X",
        "com.facebook.Facebook": "Facebook",
        "com.toyopagroup.picaboo": "Snapchat",
        "com.microsoft.Office.Word": "Word",
        "com.microsoft.Office.Excel": "Excel",
        "com.microsoft.Office.Outlook": "Outlook",
        "com.apple.mobilegarageband": "GarageBand",
        "com.apple.iMovie": "iMovie",
        "com.apple.Keynote": "Keynote 讲演",
        "com.apple.Pages": "Pages 文稿",
        "com.apple.Numbers": "Numbers 表格",
        "com.apple.clips": "Clips",
        "com.tencent.ww": "企业微信",
        "com.tencent.tim": "TIM",
        "com.xunmeng.pinduoduo": "拼多多",
        "com.taobao.fleamarket": "闲鱼",
        "com.taobao.tmall": "天猫",
        "com.autonavi.minimap": "高德地图",
        "com.autonavi.amap": "高德地图",
        "com.baidu.BaiduMap": "百度地图",
        "me.ele.ios.eleme": "饿了么",
        "com.eleme.eleme": "饿了么",
        "com.sankuai.meituan.takeoutnew": "美团外卖",
        "com.zhihu.ios": "知乎",
        "com.ss.iphone.article.News": "今日头条",
        "com.ss.iphone.ugc.live": "抖音",
        "com.tencent.mttlite": "QQ浏览器",
        "com.quark.browser": "夸克",
        "com.tencent.qqmail": "QQ邮箱",
        "com.netease.news": "网易新闻",
        "com.youku.YouKu": "优酷",
        "com.qiyi.iphone": "爱奇艺",
        "com.tencent.live4iphone": "腾讯视频",
        "com.kuaishou.nebula": "快手",
        "com.jiangjia.gif": "快手",
        "com.ximalaya.TingApple": "喜马拉雅",
        "com.gemd.iting": "喜马拉雅",
        "com.gotokeep.keep": "Keep",
        "com.dianping.dpscope": "大众点评",
        "ctrip.com": "携程",
        "com.cainiao.cnwireless": "菜鸟",
        "com.google.ios.youtube": "YouTube",
        "com.google.Drive": "Google Drive",
        "com.hammerandchisel.discord": "Discord",
        "com.tinyspeck.chatlyio": "Slack",
        "us.zoom.videomeetings": "Zoom",
        "com.microsoft.skype.teams": "Teams",
        "notion.id": "Notion",
        "com.burbn.barcelona": "Threads",
        "com.linkedin.LinkedIn": "领英",
        "com.openai.chat": "ChatGPT",
        "com.bot.doubao": "豆包",
        "com.anthropic.claude": "Claude",
        "com.deepseek.chat": "DeepSeek",
        "com.google.gemini": "Gemini",
        "com.moonshot.kimichat": "Kimi",
        "com.tencent.hunyuan.app.chat": "元宝",
        "com.aliyun.ios.tongyi": "千问",
    ]

    private static func knownURL(for bundleIdentifier: String) -> URL? {
        let schemes: [String: String] = [
            "com.apple.mobilesafari": "x-web-search://",
            "com.apple.MobileSMS": "sms://",
            "com.apple.mobilemail": "mailto:",
            "com.apple.Maps": "maps://",
            "com.apple.Music": "music://",
            "com.apple.mobilecal": "calshow://",
            "com.apple.mobilenotes": "mobilenotes://",
            "com.apple.mobileslideshow": "photos-redirect://",
            "com.apple.AppStore": "itms-apps://",
            "com.apple.weather": "weather://",
            "com.apple.facetime": "facetime://",
            "com.apple.DocumentsApp": "shareddocuments://",
            "com.apple.Passbook": "shoebox://",
            "com.apple.shortcuts": "shortcuts://",
            "com.apple.Health": "x-apple-health://",
            "com.apple.FindMy": "findmy://",
            "com.apple.reminders": "x-apple-reminderkit://",
            "com.apple.MobileAddressBook": "contact://",
            "com.apple.news": "applenews://",
            "com.apple.podcasts": "podcasts://",
            "com.apple.tv": "videos://",
            "com.apple.iBooks": "itms-books://",
            "com.apple.Home": "com.apple.home://",
            "com.apple.mobiletimer": "clock-worldclock://",
            "com.apple.Passwords": "passwordmanager://",
            "com.apple.Bridge": "itms-watch://",
            "com.apple.Fitness": "fitnessapp://",
            "com.apple.Translate": "translate://",
            "com.apple.freeform": "freeform://",
            "com.apple.Journal": "journal://",
            "com.apple.VoiceMemos": "voicememos://",
            "com.apple.calculator": "calc://",
            "com.apple.Tips": "tips://",
            "com.apple.tips": "tips://",
            "com.tencent.xin": "weixin://",
            "com.tencent.xinWeChat": "weixin://",
            "com.tencent.mqq": "mqq://",
            "com.alipay.iphoneclient": "alipay://",
            "com.alipay.iphoneclient.AlipayWallet": "alipay://",
            "com.taobao.taobao4iphone": "taobao://",
            "com.laiwang.DingTalk": "dingtalk://",
            "com.ss.iphone.ugc.Aweme": "snssdk1128://",
            "com.xingin.discover": "xhsdiscover://",
            "tv.danmaku.bilianime": "bilibili://",
            "com.bilibili.bilianime": "bilibili://",
            "com.netease.cloudmusic": "orpheus://",
            "com.kugou.kugou1002": "kugou://",
            "com.tencent.QQMusic": "qqmusic://",
            "com.baidu.BaiduMobile": "baiduboxapp://",
            "com.meituan.imeituan": "imeituan://",
            "com.didi.kuaidi": "diditaxi://",
            "com.xiaojukeji.didi": "diditaxi://",
            "com.jingdong.app.mall": "openapp.jdmobile://",
            "com.360buy.jdmobile": "openapp.jdmobile://",
            "com.sina.weibo": "sinaweibo://",
            "ph.telegra.Telegraph": "tg://",
            "net.whatsapp.WhatsApp": "whatsapp://",
            "com.burbn.instagram": "instagram://",
            "com.zhiliaoapp.musically": "tiktok://",
            "com.google.chrome.ios": "googlechrome://",
            "com.google.Gmail": "googlegmail://",
            "com.google.Maps": "comgooglemaps://",
            "com.spotify.client": "spotify://",
            "com.atebits.Tweetie2": "twitter://",
            "com.facebook.Facebook": "fb://",
            "com.toyopagroup.picaboo": "snapchat://",
            "com.microsoft.Office.Word": "ms-word://",
            "com.microsoft.Office.Excel": "ms-excel://",
            "com.microsoft.Office.Outlook": "ms-outlook://",
            "com.tencent.ww": "wxwork://",
            "com.xunmeng.pinduoduo": "pinduoduo://",
            "com.taobao.fleamarket": "fleamarket://",
            "com.autonavi.minimap": "amapuri://",
            "com.autonavi.amap": "amapuri://",
            "com.zhihu.ios": "zhihu://",
            "com.google.ios.youtube": "youtube://",
            "us.zoom.videomeetings": "zoomus://",
            "com.hammerandchisel.discord": "discord://",
            "com.kuaishou.nebula": "kwai://",
            "com.jiangjia.gif": "kwai://",
            "me.ele.ios.eleme": "eleme://",
            "com.eleme.eleme": "eleme://",
            "com.taobao.tmall": "tmall://",
            "com.cainiao.cnwireless": "cainiao://",
            "com.ximalaya.TingApple": "iting://",
            "com.gemd.iting": "iting://",
            "com.gotokeep.keep": "keep://",
            "notion.id": "notion://",
            "com.tinyspeck.chatlyio": "slack://",
            "com.microsoft.skype.teams": "msteams://",
            "com.quark.browser": "quark://",
            "tv.danmaku.bilibilihd": "bilibili://",
            "com.ss.iphone.article.News": "snssdk141://",
            "com.linkedin.LinkedIn": "linkedin://",
            "com.burbn.barcelona": "barcelona://",
            "com.openai.chat": "chatgpt://",
            "com.bot.doubao": "doubao://",
            "com.anthropic.claude": "claude://",
            "com.deepseek.chat": "deepseek://",
            "com.google.gemini": "googlegemini://",
            "com.moonshot.kimichat": "kimichat://",
            "com.tencent.hunyuan.app.chat": "hunyuan://",
            "com.aliyun.ios.tongyi": "tongyi://",
        ]
        guard let raw = schemes[bundleIdentifier] else { return nil }
        return URL(string: raw)
    }

    private static func alternateKnownURLs(for bundleIdentifier: String) -> [URL] {
        let extras: [String: [String]] = [
            "com.apple.MobileSMS": ["sms://", "imessage://", "messages://"],
            "com.apple.mobilesafari": ["https://www.apple.com"],
            "com.apple.mobilemail": ["message://"],
            "com.apple.MobileAddressBook": ["contacts-sensitive://"],
            "com.apple.Fitness": ["activitytoday://"],
            "com.apple.Passbook": ["wallet://", "shoebox://"],
            "com.apple.mobiletimer": ["clock-alarm://", "clock-timer://", "clock-stopwatch://"],
            "com.apple.AppStore": ["itms-apps://apps.apple.com"],
            "com.apple.podcasts": ["pcast://"],
            "com.apple.iBooks": ["ibooks://"],
            "com.apple.reminders": ["x-apple-reminder://"],
            "com.apple.Passwords": ["passwords://"],
            "com.tencent.xin": ["wechat://", "weixin://dl/chat"],
            "com.tencent.xinWeChat": ["wechat://"],
            "com.alipay.iphoneclient": ["alipays://"],
            "com.taobao.taobao4iphone": ["tbopen://"],
            "com.ss.iphone.ugc.Aweme": ["aweme://", "douyin://"],
            "com.xingin.discover": ["xiaohongshu://"],
            "com.tencent.mqq": ["mqqapi://"],
            "com.openai.chat": ["openai://", "com.openai.chat://"],
            "com.bot.doubao": ["snssdk3102://"],
            "com.google.gemini": ["gemini://"],
            "com.anthropic.claude": ["claude-ai://"],
        ]
        return (extras[bundleIdentifier] ?? []).compactMap(URL.init(string:))
    }

    /// `UIApplication.responds(to:)` 查的是实例方法，会把类方法 `sharedApplication` 判成不存在，
    /// 于是所有 `open` 都被跳过。这里直接取类方法实现。
    private static func sharedApplication() -> UIApplication? {
        guard !isAppExtension else { return nil }
        let selector = NSSelectorFromString("sharedApplication")
        guard let method = class_getClassMethod(UIApplication.self, selector) else { return nil }
        typealias Function = @convention(c) (AnyClass, Selector) -> UIApplication
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(UIApplication.self, selector)
    }

    private static func openURL(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        let work: () -> Void = {
            guard let app = sharedApplication() else {
                completion?(false)
                return
            }
            app.open(url, options: [:]) { success in
                completion?(success)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

nonisolated extension UIImage {
    /// 真机第三方图标接口经常返回纯黑/近黑方块，不能当正式 App 图标用。
    var hub_isVisuallyBlank: Bool {
        guard size.width >= 8, size.height >= 8, let cgImage else { return true }
        let w = 12
        let h = 12
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return true }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var opaque = 0
        var colorful = 0
        var nearWhite = 0
        var sum = 0
        var sum2 = 0
        for i in 0..<(w * h) {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])
            let a = Int(pixels[i * 4 + 3])
            if a < 16 { continue }
            opaque += 1
            let maxc = max(r, g, b)
            let minc = min(r, g, b)
            if maxc - minc > 18 { colorful += 1 }
            if minc >= 232 { nearWhite += 1 }
            let y = (r * 3 + g * 6 + b) / 10
            sum += y
            sum2 += y * y
        }
        if opaque < 8 { return true }
        // 模拟器 / 无图标 bundle 的「白底网格」占位图：几乎全是近白像素。
        if nearWhite * 100 >= opaque * 92 { return true }
        let mean = Double(sum) / Double(opaque)
        let variance = Double(sum2) / Double(opaque) - mean * mean
        if colorful >= 3 { return false }
        if mean > 22 && mean < 238 && variance > 90 { return false }
        return true
    }

    /// Family Controls 快照经常是大画布里一枚小图标，铺到蜂巢会显得异常小。
    var hub_isUnfilledIcon: Bool {
        guard size.width >= 8, size.height >= 8, let cgImage else { return true }
        let w = 32
        let h = 32
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return true }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                if pixels[(y * w + x) * 4 + 3] < 24 { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return true }
        let coverage = Double((maxX - minX + 1) * (maxY - minY + 1)) / Double(w * h)
        return coverage < 0.5
    }

    /// 裁掉透明边后的启动图标。纯色占位图返回 nil。
    func hub_preparedLauncherIcon() -> UIImage? {
        let cropped = hub_croppedToOpaqueContent() ?? self
        guard !cropped.hub_isVisuallyBlank else { return nil }
        return cropped
    }

    func hub_pngData(maxPixelSide: CGFloat) -> Data? {
        let maxPx = max(64, min(maxPixelSide, 1024))
        let pixelW = size.width * scale
        let pixelH = size.height * scale
        guard pixelW > 0, pixelH > 0 else { return pngData() }
        let factor = maxPx / max(pixelW, pixelH)
        let tw = max(1, (pixelW * min(factor, 1)).rounded(.up))
        let th = max(1, (pixelH * min(factor, 1)).rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tw, height: th), format: format)
        return renderer.pngData { _ in
            draw(in: CGRect(x: 0, y: 0, width: tw, height: th))
        }
    }

    /// Family Controls / ImageRenderer 快照常是大画布里一枚小图；裁成正方形供蜂巢使用。
    func hub_normalizedLauncherIconPNG(maxPixelSide: CGFloat = 512) -> Data? {
        let source = hub_croppedToOpaqueContent() ?? self
        let side = max(64, min(maxPixelSide, 512))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let data = renderer.pngData { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            let srcSize = source.size
            guard srcSize.width > 0, srcSize.height > 0 else { return }
            let scale = min(CGFloat(side) / srcSize.width, CGFloat(side) / srcSize.height)
            let w = srcSize.width * scale
            let h = srcSize.height * scale
            let rect = CGRect(x: (CGFloat(side) - w) * 0.5, y: (CGFloat(side) - h) * 0.5, width: w, height: h)
            source.draw(in: rect)
        }
        guard let image = UIImage(data: data), !image.hub_isVisuallyBlank else {
            return hub_pngData(maxPixelSide: maxPixelSide)
        }
        return data
    }

    private func hub_croppedToOpaqueContent() -> UIImage? {
        guard let cgImage else { return nil }
        let w = cgImage.width
        let h = cgImage.height
        guard w > 4, h > 4 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                if pixels[(y * w + x) * 4 + 3] < 24 { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = max(1, Int(Double(max(maxX - minX, maxY - minY)) * 0.04))
        let x0 = max(0, minX - pad)
        let y0 = max(0, minY - pad)
        let x1 = min(w - 1, maxX + pad)
        let y1 = min(h - 1, maxY + pad)
        let rect = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: imageOrientation)
    }
}
#endif
