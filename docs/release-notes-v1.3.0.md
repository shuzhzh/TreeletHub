## TreeletHub 1.3.0 for macOS（DMG）

配套源码同时覆盖蜂巢启动墙、一次性 Pro 买断与 Codex 深链接控制。国内正式下载走 Cloudflare CDN；GitHub Releases 作为开发备用。

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

- 不再用辅助功能 / 自动化向 ChatGPT、Cursor 注入按键。
- **Codex** 改为深链接 + 本机 Codex CLI；ChatGPT / Cursor 在启动墙中仅启动对应应用。

### 下载与分发

正式 Mac 直装包（官网按钮同一地址，覆盖更新，无需改链接）：

**https://models.appda.store/treelethub/TreeletHub.dmg**

产品页：[treelet.us/treelethub](https://treelet.us/treelethub/)（[English](https://treelet.us/treelethub/en/)）。

GitHub 附件：`TreeletHub.dmg`（[latest 直链](https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg)）、`TreeletHub-Mac-1.3.0.dmg`。

### 安装

1. 下载 DMG 并打开。
2. 将 **TreeletHub** 拖入「应用程序」文件夹。
3. 首次打开若提示无法验证开发者：前往「系统设置 → 隐私与安全性」允许，或右键 App 选择「打开」。
4. 允许 **本地网络** 访问，以便与手机配对。
5. 使用键盘启动器时，再允许 **输入监控**。

### 系统要求

- macOS 14.6 或更高版本
- 遥控需同一 Wi‑Fi 下的 iPhone / iPad 或 Android，并先安装本 Mac 客户端
