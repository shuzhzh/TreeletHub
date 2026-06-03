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

1. 使用 App Store 链接生成二维码：  
   `https://apps.apple.com/app/treelethub-%E6%95%88%E7%8E%87-%E6%8E%A7%E5%88%B6%E5%8F%B0/id6762348247`
2. 保存为 `assets/ios-app-qr.png`。
3. 在 `README.md` 中取消 iOS 二维码图片的 HTML 注释。
4. 提交并 push。

## 截图（可选）

将宣传截图放入 `assets/screenshots/`，并在 README 中引用，便于 GitHub 仓库首页展示。
