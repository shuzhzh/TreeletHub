## TreeletHub 1.2.7 for macOS（DMG）

### 新功能：AI 控制键盘桥接

与 iPhone 上的 **AI 控制键盘**配合：在九宫格点按 ChatGPT / Codex / Cursor 后，Mac 端接收指令并驱动目标应用。

- 支持 **ChatGPT**（含 Codex 工作流）、**ChatGPT Classic**、**Cursor**。
- Agent 状态尽量从本地 Codex 会话数据近似同步。
- 命令键、摇杆、推理旋钮、听写结束写回输入框等。
- 按目标应用分别持久化键位映射。

请搭配 **iPhone 端 1.2.5 或更高** 以获得完整体验。详见 [使用说明 · AI 控制键盘](USER_GUIDE.zh-CN.md#ai-控制键盘iphone--chatgpt--codex--cursor)。

### 权限与安全

- 首次使用请在「系统设置 → 隐私与安全性」中允许 **辅助功能** 与 **自动化**（系统事件 + ChatGPT / Cursor）。
- 默认不向命令面板自动打字；可选手动开启。
- 指令节流与防刷屏，避免误触导致目标应用失控。

### 其它修复

- 修复打字音效相关源码截断导致的编译问题。
- 移除 Mac App Store 不支持的 temporary-exception 权限声明，保留运行时自动化授权提示。

### 安装包

- 附件：`TreeletHub.dmg`（与 [README 最新下载链接](https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg) 一致）、`TreeletHub-Mac-1.2.7.dmg`。

### 安装

1. 下载 DMG 并打开。
2. 将 **TreeletHub** 拖入「应用程序」文件夹。
3. 首次打开若提示无法验证开发者：前往「系统设置 → 隐私与安全性」允许，或右键 App 选择「打开」。
4. 允许 **本地网络** 访问，以便与手机配对。
5. 使用 AI 控制键盘时，再允许 **辅助功能** 与 **自动化**。

### 系统要求

- macOS 14.6 或更高版本
- iPhone 端 **1.2.5** 或更高以获得完整 AI 控制键盘体验
