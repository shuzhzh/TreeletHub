# 发布 Mac DMG 到 GitHub Releases

本仓库通过 **GitHub Releases** 分发 Mac 直装包，不提交 DMG 到 git 历史。

## 维护者步骤

1. 在 Xcode 中 Archive **TreeletHub_Mac**，导出 **Developer ID** 或分发用 **DMG**。
2. 打开 [Releases](https://github.com/shuzhzh/TreeletHub/releases) → **Draft a new release**。
3. **Tag**：建议语义化版本，例如 `v1.0.0`。
4. **Title**：例如 `TreeletHub 1.0.0 for macOS (DMG)`。
5. 将 DMG 拖到 **Attach binaries**，建议文件名：`TreeletHub.dmg`（或 `TreeletHub-<version>.dmg`，并同步更新 README 中的下载说明）。
6. 在 Release notes 中写明：最低 macOS 版本、是否需允许本地网络、与 App Store 版的差异。
7. 发布 **Publish release**。

## README 直链（可选）

若固定文件名为 `TreeletHub.dmg`，可在 README 使用：

`https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg`

（仅当 Release 附件使用该文件名时有效。）

## iOS 二维码

已包含在 `assets/ios-app-qr.png`，并在 `README.md` 中展示。更新二维码时替换该文件并 push 即可。

## 截图（可选）

将宣传截图放入 `assets/screenshots/`，并在 README 中引用，便于 GitHub 仓库首页展示。
