## TreeletHub iOS 1.2.4 · Apple Watch 伴侣 App v1.0

### 新功能：Apple Watch 遥控

在已配对的 iPhone 旁，用 Apple Watch 控制 Mac 九宫格——底层仍由 iPhone 持有与 Mac 的局域网连接，Watch 通过 WatchConnectivity 同步状态并转发操作。

- **Watch 九宫格控制台** — 镜像 iPhone 上的分页与图标；垂直滑动切换页面，点按启动应用或触发快捷项。
- **Watch 配对** — 在手表上输入 6 位配对码，经 iPhone 完成与 Mac 的连接；支持缓存配对提示与取消扫描。
- **快捷项** — 支持静音切换、播放/暂停、亮度等快捷控制，与 iPhone 端一致。
- **图标同步** — iPhone 按页推送 PNG 图标到 Watch，减少 applicationContext 体积限制带来的布局缺失。
- **断开连接** — 控制台设置页可一键断开。

### 配套变更

- 新增 `TreeletHubWatchApp Watch App` 目标，并由 iOS App 嵌入 Watch Content。
- iPhone 端 `HubIOSWatchBridge`：将 `HubIOSClient` 状态推给 Watch，并将 Watch 操作转回客户端。
- 共享层 `HubPhoneWatchSync`：定义快照与消息协议（配对、点按、控制、图标分页等）。
- 共享拖拽修饰在 watchOS 上跳过，避免不可用的 Drop 能力。
- Watch / iPhone 本地化字符串（中英等）。

### 使用说明

1. 在 iPhone 上更新并打开 TreeletHub，确保已与 Mac 配对，或准备好 6 位配对码。
2. 在 Apple Watch 上打开 TreeletHub；手表需与同一 iPhone 配对，且 iPhone App 可达。
3. 未连接时在手表输入配对码并连接；已连接后直接点按九宫格遥控 Mac。

### 系统要求

- iPhone：与本包部署目标一致（iOS / TreeletHub iOS **1.2.4**，build **19**）
- Apple Watch：watchOS **10.6** 或更高
- Mac：已安装并运行 TreeletHub 桌面端，且与 iPhone 同一局域网

### 说明

- Watch 本身不直接连 Mac；遥控依赖 iPhone App 在线与可达。
- 本说明对应源码与工程中的 Watch 伴侣集成；App Store 上架后以商店版本说明为准。
