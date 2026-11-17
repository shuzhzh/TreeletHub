完整变更记录见仓库根目录 [CHANGELOG.md](../CHANGELOG.md)。

## TreeletHub 1.3.2（全端） / TreeletHub Pro for macOS

营销版本全端统一为 **1.3.2**（Mac、iOS、Watch、桌面小组件、Android）。Apple `CURRENT_PROJECT_VERSION` = **34**；Android `versionCode` = **7**。

App Store Connect（2026-11-17 核对）：

- **Mac**：线上仍为 **1.3.0**（build 29）；曾有空的 **1.3.1**（`PREPARE_FOR_SUBMISSION`，未挂 build）。本版以 **1.3.2** 提交。
- **iOS**：线上已是 **1.3.1**（build 33），故新功能必须升到 **1.3.2**。

官网直装包显示名为 **TreeletHub Pro**（Mac App Store 伴侣端仍为 TreeletHub）。国内下载仍走 Cloudflare CDN。

### 手机键鼠遥控（仅官网 Pro）

- 在 Mac「添加快捷方式」加入 **键盘与鼠标**，手机蜂巢点该格即可当触控板与键盘用。
- 单指移动 / 点按左键、双指滚动、文字与常用修饰键；进阶手势含拖移、捏合、旋转、智能缩放与三指滑动等。
- **Mac App Store 版没有此项**，手机端也不会出现对应格子。
- 首次使用请在「系统设置 → 隐私与安全性 → **辅助功能**」允许 TreeletHub Pro。注入仅在本机、不上传。

### 灵动岛

- 展开 / 贴边态均可 **拖拽边缘调整宽高**，尺寸会记住。
- 岛变大后，字号、图标与卡片随比例放大。
- 输入监控权限探测更稳；键盘启动器只依赖 **输入监控**。

### 其它

- 主窗口默认尺寸与权限设置页跳转适配新版系统设置。
- 与已配对 iPhone / Android 同步 `remoteInputAvailable`，App Store Mac 上自动隐藏键鼠标块。

### 下载

**https://models.appda.store/treelethub/TreeletHub.dmg**

产品页：[treelet.us/treelethub](https://treelet.us/treelethub/)

### 安装注意

1. 若从 1.3.0 覆盖安装，显示名可能变为 TreeletHub Pro。  
2. 使用手机键鼠时额外允许 **辅助功能**；键盘启动器仍只需 **输入监控**。  
3. 系统要求：macOS 14.6 或更高。
