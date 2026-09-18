## TreeletHub 1.2.8 for macOS

配套源码同时更新 iPhone / Watch / Android；Mac 安装包走 Cloudflare CDN，不再以 Mac App Store / GitHub Releases 作为国内主下载链。

### 蜂巢启动墙

- 九宫格改为 **Watch App View 风格的蜂巢启动墙**：捏合缩放、拖动浏览，虚线「+」添加应用 / 网页快捷方式 / 系统操作。
- 新装首次为空时，按本机已安装情况预填常用系统应用（只执行一次，清空后不再自动填回）。
- 支持跨页拖拽换位；免费最多 **10** 个应用 / 快捷方式，解锁 Pro 后不限数量。

### Pro：一次性买断（非订阅）

- 新商品 `com.treelet.treelethub.mac.pro.lifetime`，标价 **$9.99**，不自动续费。
- 已购买旧年付订阅且仍在有效期内的用户，继续视为已解锁。
- 解锁后可用无限启动项、**灵动岛**、**键盘启动器**。入口在主窗口配对码下方开关，或右上角齿轮菜单。

### 灵动岛与键盘启动器

- 未开启时展示效果预览图；首次启动有功能介绍。
- 灵动岛水平始终锚在当前屏幕正中，展开态加高以容纳蜂巢启动台；贴边热区悬停直接展开大面板。
- 键盘启动器仍需「输入监控」；打字音效暂不开放。

### Codex 控制（无按键注入）

- 不再用辅助功能 / 自动化向 ChatGPT、Cursor 注入按键（符合 App Store 2.4.5）。
- **Codex** 改为深链接 + 本机 Codex CLI；ChatGPT / Cursor 在启动墙中仅启动对应应用。
- iPhone 端已移除控制键盘、听写与麦克风权限；Android 端控制键盘仅保留 Codex。

### 下载与分发

正式 Mac 直装包：

**https://models.appda.store/treelethub/TreeletHub.dmg**

产品页：[treelet.us/treelethub](https://treelet.us/treelethub/)（[English](https://treelet.us/treelethub/en/)）。GitHub Releases 仅作开发备用。

### 系统要求

- macOS 14.6 或更高版本
- 遥控需同一 Wi‑Fi 下的 iPhone / iPad 或 Android，并先安装本 Mac 客户端

---

## 同批次：iPhone / Watch / Android 源码

尚未单独升 iOS / Android 商店版本号；以下改动已包含在本仓库。

### iPhone

- Apps 页改为蜂巢启动墙（长按编辑、拖拽换位）；连接页嵌入功能介绍。
- 移除 AI 控制键盘、本机听写与订阅门控界面。
- 布局乐观换位，减少等待 Mac 回传时的图标卡住。

### Apple Watch

- 控制台改为同一套蜂巢启动墙；不再按订阅裁切首页。

### Android

- 点按 ChatGPT / Cursor 只启动 Mac 应用；控制键盘仅对 **Codex** 打开，默认键位改为 Skills / 定时任务等。
