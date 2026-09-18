# Changelog

本文件记录 TreeletHub 面向用户的版本变化。GitHub 仓库首页可直接打开本页；安装包说明也在 [Releases](https://github.com/shuzhzh/TreeletHub/releases)。

## [1.3.0] — 2026-09-18（macOS，当前）

正式 Mac 直装包。蜂巢启动墙、一次性 Pro、灵动岛与键盘启动器一并发布。

### 灵动岛（Pro）

- 屏幕顶部贴边细条，悬停或点按展开为大面板。
- **系统应用**：本机已安装应用墙，可搜索、缩放图标。
- **工作台**：媒体播放、天气、剪贴板、文件暂存 / 配对等小组件并排使用。

### 键盘启动器（Pro）

- 松开 Control 唤出屏幕键盘浮层，按映射键启动应用。
- `Control + 按键` 可在任意 App 前台唤起或隐藏对应应用。
- 首次开启按应用名首字母自动填键；支持点击替换与拖拽换位。
- 需「输入监控」权限；不记录、不上传按键内容。

### 蜂巢启动墙

- Watch 风格蜂巢布局：捏合缩放、拖动浏览，虚线「+」添加应用 / 网页 / 系统操作。
- 新装首次为空时预填常用系统应用（只执行一次）。
- 免费最多 10 个；解锁 Pro 后不限数量。布局与已配对 iPhone / Android / Watch 同步。

### Pro

- 一次性 $9.99 买断（非订阅）：无限启动项、灵动岛、键盘启动器。
- 已购买旧年付且仍在有效期内的用户继续视为已解锁。

### 其它

- Codex 改为深链接 + 本机 CLI；ChatGPT / Cursor 在启动墙中只负责启动，不再注入按键。
- 国内下载走 CDN：https://models.appda.store/treelethub/TreeletHub.dmg

详细说明：[docs/release-notes-v1.3.0.md](docs/release-notes-v1.3.0.md) · [Release](https://github.com/shuzhzh/TreeletHub/releases/tag/v1.3.0)

## [1.2.8] — 2026-09-18（源码）

蜂巢启动墙、一次性 Pro、灵动岛与键盘启动器的源码合入。Mac 安装包随后以 **1.3.0** 发布。

详见 [docs/release-notes-v1.2.8.md](docs/release-notes-v1.2.8.md)。

## [1.3] — 2026-07-26（Android）

- Apps 页控制键盘（当时覆盖 ChatGPT / Codex / Cursor）。
- 按住说话（PTT）、左右滑动切页、双指下滑显示桌面。

[Release](https://github.com/shuzhzh/TreeletHub/releases/tag/android-v1.3) · [说明](docs/release-notes-android-v1.3.md)

## [1.2.7] — 2026-07-26（macOS）

- 与手机端 AI 控制键盘桥接（ChatGPT / Codex / Cursor）。
- 后续 1.3.0 已改为深链接 / 仅启动，不再向其他应用注入按键。

[Release](https://github.com/shuzhzh/TreeletHub/releases/tag/v1.2.7) · [说明](docs/release-notes-v1.2.7.md)

## 更早版本

- [macOS 1.2.6](docs/release-notes-v1.2.6.md)
- [macOS 1.2.4](docs/release-notes-v1.2.4.md)
- [macOS 1.2.3](docs/release-notes-v1.2.3.md)
- [iOS 1.2.5](docs/release-notes-ios-v1.2.5.md)
- [iOS 1.2.4](docs/release-notes-ios-v1.2.4.md)
