# TreeletHub 使用说明

[← 返回 README](../README.md) · [English](USER_GUIDE.en.md)

## 简介

TreeletHub 在 Mac 上配置应用九宫格，同一 Wi‑Fi 下的 iPhone、iPad 或 Android 手机配对后，可远程启动 Mac 应用。两端均可拖拽调整格子。

常见用法：Mac 上保持 TreeletHub 运行，在客厅或别的房间用手机唤起已放进九宫格的应用。

### 演示视频

- [演示 1](https://youtube.com/shorts/koVxMkCqO6Q)
- [演示 2](https://youtube.com/shorts/Z-G5ocFpQhQ)

---

## 下载

| 端 | 链接 |
|----|------|
| iPhone / iPad | [App Store](https://apps.apple.com/app/treelethub-%E6%95%88%E7%8E%87-%E6%8E%A7%E5%88%B6%E5%8F%B0/id6762348247) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=com.treelet.treelethub) |
| Mac | [App Store](https://apps.apple.com/app/treelethub-%E6%A1%8C%E9%9D%A2%E6%95%88%E7%8E%87%E6%8E%A7%E5%88%B6%E4%B8%AD%E5%BF%83/id6762348258) 或 [DMG](https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg) |

---

## 从 iPhone / iPad 连接 Mac

1. Mac 上打开 TreeletHub，记下 **6 位配对码**。
2. iPhone 打开「**连接 Mac**」，输入配对码并连接。
3. 首次连接允许「**本地网络**」。

Mac 上重新生成配对码后，手机需用 **新码** 重连。

---

## 从 Android 连接 Mac

1. Mac 上打开 TreeletHub，记下 **6 位配对码**。
2. Android 打开「**Connect to Mac**」，输入配对码并连接。
3. 与 Mac 保持 **同一 Wi‑Fi**；首次使用允许网络发现。若搜不到 Mac，可关闭 VPN 后重试。

Mac 上重新生成配对码后，手机需用 **新码** 重连。

---

## Mac 端九宫格设置

1. 点按格子，选择要绑定的 `.app`。
2. 拖拽已绑定的应用在格子间移动或交换。
3. 多页 Tab（Apps、Apps1…）可扩展页面；**部分页面需订阅**。
4. 可绑定网页快捷方式、系统快捷操作等（以 Mac 版界面为准）。

---

## 配对成功后（手机端）

- **Apps** 页显示与 Mac 同步的九宫格，点按启动应用。
- **设置** 中可改设备名、换背景或替换相册背景（各端保留一张自定义图）。
- 支持拖拽排序，与 Mac 同步。

### 显示桌面（仅 iPhone）

已配对时在 Apps 页 **双指下滑**，可隐藏 Mac 上全部已打开应用（含 TreeletHub）并显示桌面。

---

## AI 控制键盘（iPhone · ChatGPT / Codex / Cursor）

把 ChatGPT、Codex 或 Cursor 放进九宫格，在 iPhone 上点按它：手机不只是启动应用，而是直接进入对应的 **控制键盘**——Agent 状态灯、命令键、技能摇杆与推理旋钮。

- **Codex**：批准 / 拒绝、新会话继续、推理强度、Skills。
- **ChatGPT**：新会话、按住说话、发送、命令菜单、侧边栏。
- **Cursor**：按住说话、发送、Chat、命令面板、接受 / 拒绝改动、终端。

点右上角按钮可 **逐键重新映射**，也可恢复官方默认布局。Mac 需为 TreeletHub 开启 **辅助功能** 与 **自动化** 权限，否则控制页会提示未授权且按键无效。

### 按住说话（PTT）

1. 在控制键盘上 **按住「PTT」** 说话，手机上实时显示识别出的文字。
2. 识别全程在 **iPhone 本机** 完成，**音频不会离开手机**，只有最终文字经 Wi‑Fi 发送到 Mac。
3. **松手** 后文字自动填入 Mac 上 ChatGPT / Codex / Cursor 的输入框，确认无误后点 **Send** 发送。

350 毫秒内 **双击 PTT** 进入免提录音，再点一次结束。首次使用需允许 iPhone 的 **麦克风** 与 **语音识别** 权限。

---

## Mac 灵动岛（订阅）

有效订阅下，Mac 可开启顶部浮层，包含媒体控制、配对码、剪贴板、同步九宫格、时间与天气（WeatherKit，需定位与网络）等，以 Mac 版与权限为准。

---

## Mac 键盘启动器（订阅）

有效订阅下，Mac 主窗口可开启 **键盘启动器**：

1. 打开开关后，按提示在「系统设置 → 隐私与安全性 → **输入监控**」中允许 TreeletHub。
2. **松开 Control** 唤出屏幕键盘浮层；按已映射的按键启动应用，或 **Esc / 点击浮层外** 关闭。
3. 随时使用 **Control + 按键** 在全局唤起或隐藏对应应用（无需先打开浮层）。
4. 首次开启会按应用名称 **首字母** 自动填充键位；点击空键添加、点击已有键替换，**拖拽** 可在键位间交换应用。

适合把 Chrome、微信、终端等高频 App 绑在固定字母上，减少鼠标往返程序坞。

---

## 订阅

- 免费可用 **首页 Apps** 九宫格。
- 订阅解锁 **多页**、Mac **灵动岛** 与 Mac **键盘启动器**。
- iOS / Mac：通过 **App Store** 购买；Android 多页可通过 **Google Play Pro** 或 Mac 端有效订阅解锁（以各端设置页为准）。

---

## 权限

| 权限 | 用途 |
|------|------|
| 本地网络 | 发现 Mac、同步布局、发送启动指令 |
| 辅助功能 / 自动化（Mac） | 启动应用、AI 控制键盘按键与文字输入 |
| 输入监控（Mac，键盘启动器） | 监听 Control 与快捷键以显示浮层并启动映射应用 |
| 麦克风 / 语音识别（iPhone，按住说话） | 在本机把语音识别成文字后发送到 Mac 输入框 |
| 定位（可选） | Mac 灵动岛天气 |

---

## 相关链接

- [FAQ](FAQ.zh-CN.md)
- [官网](https://treelet.us/treelethub/)
- [隐私政策](https://treelet.us/treelethub/treelet-hub-privacy.html)
- [用户协议](https://treelet.us/treelethub/treelet-hub-terms.html)
