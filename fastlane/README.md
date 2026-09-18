# TreeletHub Fastlane 部署

本目录用于 **iOS / macOS** 的归档、TestFlight / App Store 上传，以及（可选）App Store Connect **商店文案** 的版本管理。

## 你需要准备的信息

复制 `account-A.env.example` 为 `fastlane/.env.treelet`（文件名即 `--env` 名称），填入：

| 变量 | 说明 | 从哪里获取 |
|------|------|------------|
| `FASTLANE_TEAM_ID` | Apple Developer **Team ID**（10 位） | [developer.apple.com](https://developer.apple.com/account) → Membership |
| `FASTLANE_APP_IDENTIFIER` | iOS Bundle ID | Xcode → TreeletHub target → `com.treelet.TreeletHub` |
| `FASTLANE_MAC_APP_IDENTIFIER` | Mac Bundle ID（仅 Mac 通道需要） | `com.treelet.TreeletHub-Mac` |
| `FASTLANE_SCHEME` | iOS Scheme | 默认 `TreeletHub` |
| `FASTLANE_MAC_SCHEME` | Mac Scheme | 默认 `TreeletHub_Mac_AppStore`（合规审核包） |
| `FASTLANE_MAC_CONFIGURATION` | Mac Configuration | 默认 `AppStore` |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID | App Store Connect → 用户与访问 → 集成 → App Store Connect API |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | 同上 |
| `APP_STORE_CONNECT_KEY_PATH` | `.p8` 私钥路径 | 下载后放到 `fastlane/keys/`（已在 `.gitignore`） |

可选：

| 变量 | 何时需要 |
|------|----------|
| `FASTLANE_ITC_TEAM_ID` | 同一 Apple ID 下多个 ASC 组织时 |
| `FASTLANE_USER` + 应用专用密码 | 不用 API Key、改用 Apple ID 登录时 |

**密钥文件**：将 `AuthKey_XXXXXXXXXX.p8` 放到例如 `fastlane/keys/treelet/`，路径与 `APP_STORE_CONNECT_KEY_PATH` 一致。

## 安装

```bash
cd /path/to/TreeletHub   # 含 TreeletHub.xcodeproj 的目录
bundle install             # 推荐：锁定 fastlane 版本
# 或：brew install fastlane
```

## 常用命令

```bash
# iOS → TestFlight（日常）
bundle exec fastlane ios beta --env treelet

# iOS → 仅上传 IPA（已本地 archive）
bundle exec fastlane ios beta --env treelet skip_build:true

# iOS → App Store（仅二进制，不改文案）
bundle exec fastlane ios release --env treelet

# 从 App Store Connect 拉取当前商店文案到仓库
bundle exec fastlane ios metadata_pull --env treelet

# 将 fastlane/metadata/ios 中的文案推到 ASC（解决 5.2.5 后常用）
bundle exec fastlane ios metadata_push --env treelet

# Mac → TestFlight / Mac App Store（合规包，无键盘启动器）
bundle exec fastlane mac beta --env treelet
bundle exec fastlane mac release --env treelet
```

## Guideline 5.2.5（Mac / iOS 商标）

审核信指向 **App Store Connect 里的应用名称、副标题**，不是 Xcode 里的 `CFBundleDisplayName`。

请在 ASC → **App 信息** 检查各语言：

- **不要**在 **名称 / 副标题** 里写 `Mac`、`iOS`、`iPhone`、`iPad` 等（易被认定模仿 Apple 产品命名）。
- **可以**在 **描述、截图说明、版本说明** 里用中性表述，例如「在电脑上安装伴侣端」「在手机上远程启动」——避免把平台名塞进标题行。

仓库内已提供合规示例：`fastlane/metadata/ios/`。修改后执行 `metadata_push`，再在 ASC 确认并重新提交审核。

若你当前线上名称类似「TreeletHub Mac/iOS 遥控」，请改为例如：

| 字段 | 英文建议 | 中文建议 |
|------|----------|----------|
| 名称 | `TreeletHub` | `TreeletHub` |
| 副标题 | `Remote app hub on Wi‑Fi` | `局域网应用九宫格遥控` |

（副标题 ≤ 30 字符；以你最终在 ASC 看到的字数为准。）

## 多账号

每个 Apple 开发者账号一套 API Key 与一个 `.env.<名称>`，例如：

```bash
fastlane ios beta --env accountA
fastlane ios beta --env accountB
```

## 与脚本的关系

- Mac 官网 / GitHub **全功能** `.dmg`：`./scripts/package-mac-dmg.sh`（scheme `TreeletHub_Mac` / `Release`，含键盘启动器）
- 商店分发 Mac：**必须**使用 `fastlane mac beta` / `mac release`（默认 scheme `TreeletHub_Mac_AppStore` / configuration `AppStore`）
- 切勿用全功能 Release 包直接传 App Store Connect
