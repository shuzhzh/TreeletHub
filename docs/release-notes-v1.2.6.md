## TreeletHub 1.2.6 for macOS（DMG）

### 灵动岛与 UI

- 精简灵动岛视觉：去除多余发光动画与装饰，更接近系统原生质感。
- 修复无边框窗口下 Material 导致的半透明外圈背景问题。
- 播放页文案与布局收敛；时钟、收起态信息条更易读。

### 正在播放（App Store 合规）

- 移除私有 MediaRemote 框架依赖，符合 Mac App Store 审核要求。
- 「音乐」App 仍显示完整曲目、进度与封面（AppleScript + scripting-targets）。
- 其他 App（Chrome、抖音等）通过 Core Audio 显示图标与出声状态；修复 Helper 子进程无法识别的问题。

### 打字音效

- 重写机械轴 / 打字机合成模型：双瞬态、外壳共鸣、立体声、松键回弹。
- 打字机预设改为程序化合成；快速连打多声部并发。

### 安装包

- 新增 `TreeletHub_Mac_release/build-dmg.sh`，用于生成带背景图的 DMG。
- 附件：`TreeletHub.dmg`（与 README 最新下载链接一致）、`TreeletHub-Mac-1.2.6.dmg`。

### 安装

1. 下载 DMG 并打开。
2. 将 **TreeletHub** 拖入「应用程序」文件夹。
3. 首次打开若提示无法验证开发者：前往「系统设置 → 隐私与安全性」允许，或右键 App 选择「打开」。
4. 允许 **本地网络** 访问，以便与手机配对。

### 系统要求

- macOS 14.6 或更高版本
