# TreeletHub 使用说明

[← 返回 README](../README.md) · [English](USER_GUIDE.en.md)

## 简介

TreeletHub 在 Mac 上以**蜂巢启动墙**收纳常用应用与快捷方式；同一 Wi‑Fi 下的 iPhone、iPad 或 Android 配对后，可远程启动这些 Mac 应用。布局会在设备间同步。

常见用法：Mac 上保持 TreeletHub 运行，在客厅或别的房间用手机唤起已放进启动墙的应用。

### 演示视频

- [演示 1](https://youtube.com/shorts/koVxMkCqO6Q)
- [演示 2](https://youtube.com/shorts/Z-G5ocFpQhQ)

---

## 下载

| 端 | 链接 |
|----|------|
| iPhone / iPad | [App Store](https://apps.apple.com/app/treelethub-%E6%95%88%E7%8E%87-%E6%8E%A7%E5%88%B6%E5%8F%B0/id6762348247) |
| Android | [CDN APK](https://models.appda.store/treelethub/TreeletHub.apk) · [Google Play](https://play.google.com/store/apps/details?id=com.treelet.treelethub) |
| Mac | [CDN DMG](https://models.appda.store/treelethub/TreeletHub.dmg) |

仅安装手机端无法使用——必须同时安装 Mac 客户端并配对。

---

## 从 iPhone / iPad 连接 Mac

1. **先安装 Mac 版**（官网 DMG），再在 Mac 打开 TreeletHub，记下 **6 位配对码**。
2. iPhone 打开「**连接 Mac**」，输入配对码并连接。
3. 首次连接允许「**本地网络**」。

Mac 上重新生成配对码后，手机需用 **新码** 重连。

---

## 从 Android 连接 Mac

1. **先安装 Mac 版**，再在 Mac 打开 TreeletHub，记下 **6 位配对码**。
2. Android 打开「**Connect to Mac**」，输入配对码并连接。
3. 与 Mac 保持 **同一 Wi‑Fi**；首次使用允许网络发现。若搜不到 Mac，可关闭 VPN 后重试。

Mac 上重新生成配对码后，手机需用 **新码** 重连。

---

## Mac 端：添加应用与蜂巢启动墙

1. 点按主窗口 **「+」**，或蜂巢墙上的虚线 **「+」**，绑定 `.app`、网页快捷方式或系统快捷操作。
2. **捏合缩放**、**拖动浏览**；**Control-点击** 格子可清除。
3. 免费最多 **10** 个应用 / 快捷方式；解锁 Pro 后不限数量。
4. 右上角 **齿轮** 可开关灵动岛、键盘启动器，以及语言与 Pro 解锁。

主窗口配对码下方也有灵动岛 / 键盘启动器的紧凑开关。

---

## 配对成功后（手机端）

- **Apps** 显示与 Mac 同步的蜂巢启动墙，点按启动应用。
- **设置** 中可改设备名、换背景或替换相册背景（各端保留一张自定义图）。
- 底栏在 Apps 与设置之间切换。

### 显示桌面（iPhone / Android）

已配对时在 Apps 页 **双指下滑**，可隐藏 Mac 上全部已打开应用（含 TreeletHub）并显示桌面。

---

## Codex 控制（Android）

把 **Codex** 放进启动墙后，在 **Android** 上点按可打开控制键盘（Skills、定时任务、设置等）。Mac 通过 **深链接 / Codex CLI** 驱动，不再向目标应用注入按键。

**ChatGPT** 与 **Cursor**（以及 iPhone 上的所有应用）点按后只启动 Mac 上的对应应用，不再进入控制键盘。

---

## Mac 灵动岛（Pro）

解锁 Pro 后，在 Mac 主窗口或 **设置（齿轮）** 开启「灵动岛」。屏幕顶部贴边细条，悬停或点按展开为大面板：

- **系统应用**：本机已安装应用墙，可搜索、缩放图标。
- **工作台**：媒体播放、天气（WeatherKit，可选定位）、剪贴板、文件暂存 / 配对等小组件。

---

## Mac 键盘启动器（Pro）

解锁 Pro 后，在 Mac 主窗口或设置菜单开启 **键盘启动器**：

1. 打开开关后，按提示在「系统设置 → 隐私与安全性 → **输入监控**」中允许 TreeletHub。
2. **松开 Control** 唤出屏幕键盘浮层；按已映射的按键启动应用，或 **Esc / 点击浮层外** 关闭。
3. 随时使用 **Control + 按键** 在全局唤起或隐藏对应应用（无需先打开浮层）。
4. 首次开启会按应用名称 **首字母** 自动填充键位；点击空键添加、点击已有键替换，**拖拽** 可在键位间交换应用。

适合把 Chrome、微信、终端等高频 App 绑在固定字母上，减少鼠标往返程序坞。

---

## Pro 解锁（一次性买断）

- 免费可用最多 **10** 个应用 / 快捷方式。
- **一次性 $9.99** 解锁 Pro（非订阅、不自动续费）：无限添加、Mac **灵动岛**、Mac **键盘启动器** 等全部 Pro 功能。
- iOS / Mac：通过 **App Store** 内购；Mac 解锁状态会同步到已配对手机。Android 解锁以各端设置页为准。

---

## 权限

| 权限 | 用途 |
|------|------|
| 本地网络 | 发现 Mac、同步布局、发送启动指令 |
| 输入监控（Mac，键盘启动器） | 监听 Control 与快捷键以显示浮层并启动映射应用 |
| 定位（可选） | Mac 灵动岛天气 |
| 屏幕录制（Mac，灵动岛） | 按系统要求为浮层能力授权（以权限说明为准） |

---

## 相关链接

- [FAQ](FAQ.zh-CN.md)
- [官网](https://treelet.us/treelethub/)
- [隐私政策](https://treelet.us/treelethub/treelet-hub-privacy.html)
- [用户协议](https://treelet.us/treelethub/treelet-hub-terms.html)
