## TreeletHub 1.2.7 for macOS

### 新功能：AI 控制键盘桥接

与 iPhone 上的 AI 控制键盘配合：手机点按九宫格中的 ChatGPT / Codex / Cursor 后，Mac 端接收指令并驱动目标应用。

- 支持 **ChatGPT**（含 Codex 工作流）、**ChatGPT Classic**、**Cursor**。
- Agent 状态尽量从本地 Codex 会话数据近似同步。
- 命令键、摇杆、推理旋钮、听写结束写回输入框等。
- 按目标应用分别持久化键位映射。

### 权限与安全

- 新增自动化 / Apple Events 相关说明与沙盒例外（System Events、目标应用、`.codex` 只读）。
- 默认不向命令面板自动打字；可选手动开启。
- 指令节流与防刷屏，避免误触导致目标应用失控。

### 其它修复

- 修复打字音效相关源码截断导致的编译问题。

### 使用说明

1. 更新并打开 Mac TreeletHub，与 iPhone 配对。
2. 首次使用 AI 控制键盘时，在 **系统设置 → 隐私与安全性** 中允许 TreeletHub 的 **辅助功能** 与 **自动化**（系统事件 + ChatGPT / Cursor）。
3. 在 iPhone 九宫格点按 ChatGPT / Codex / Cursor 进入控制键盘。

### 系统要求

- macOS 14.6 或更高
- iPhone 端 **1.2.5** 或更高以获得完整 AI 控制键盘体验

### App Store / DMG「What's New」

见中英文商店文案（与 iOS 1.2.5 配套）。
