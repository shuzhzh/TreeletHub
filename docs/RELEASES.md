# 发布 Mac DMG 到 GitHub Releases

本仓库通过 **GitHub Releases** 分发 Mac 直装包。DMG 放在 `releases/TreeletHub.dmg`，推送 **版本 tag** 后由 [GitHub Actions](https://github.com/shuzhzh/TreeletHub/actions/workflows/release-dmg.yml) 自动创建 Release 并上传附件。

## 维护者步骤

1. 在 Xcode 中 Archive **TreeletHub_Mac**，导出 **DMG**。
2. 复制到本仓库：`cp ~/Downloads/Treelethub.dmg releases/TreeletHub.dmg`
3. 编写 `docs/release-notes-vX.Y.Z.md`（与 tag 同名，如 `v1.2.3` → `release-notes-v1.2.3.md`）。
4. 更新 `README.md` 中的版本号与下载链接（如需要）。
5. 提交并推送 `main`，再打 tag 并推送：
   ```bash
   git add releases/TreeletHub.dmg docs/release-notes-v1.2.3.md README.md
   git commit -m "Release macOS v1.2.3 DMG"
   git push origin main
   git tag v1.2.3
   git push origin v1.2.3
   ```
6. 在 [Actions](https://github.com/shuzhzh/TreeletHub/actions) 确认 workflow 成功；Release 出现在 [Releases](https://github.com/shuzhzh/TreeletHub/releases)。

## README 直链（可选）

若固定文件名为 `TreeletHub.dmg`，可在 README 使用：

`https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg`

（仅当 Release 附件使用该文件名时有效。）

## iOS 二维码

已包含在 `assets/ios-app-qr.png`，并在 `README.md` 中展示。更新二维码时替换该文件并 push 即可。

## 截图（可选）

将宣传截图放入 `assets/screenshots/`，并在 README 中引用，便于 GitHub 仓库首页展示。
