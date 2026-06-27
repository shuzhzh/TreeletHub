import Foundation

/// 本地缓存的配对信息，用于下次启动尝试自动重连。
struct HubPairingCache: Codable, Equatable {
    var pin: String
    /// 上次成功连接时 Bonjour 显示名（主机名），用于在多台 Mac 时优先匹配。
    var bonjourServiceName: String?

    static let userDefaultsKey = "treelethub.pairing.cache.v1"
}
