# 发布 Mac DMG 到 GitHub Releases

本仓库通过 **GitHub Releases** 分发 Mac 直装包。DMG 放在 `releases/TreeletHub.dmg`，推送 **版本 tag** 后由 [GitHub Actions](https://github.com/shuzhzh/TreeletHub/actions/workflows/release-dmg.yml) 自动创建 Release 并上传附件。

## 维护者步骤

1. 用 `TreeletHub_Mac_release/build-dmg.sh X.Y.Z` 生成 fancy DMG（见 skill `package-mac-dmg`）。
2. 复制到本仓库：
   ```bash
   cp TreeletHub_Mac_release/TreeletHub-Mac-X.Y.Z.dmg releases/TreeletHub.dmg
   cp TreeletHub_Mac_release/TreeletHub-Mac-X.Y.Z.dmg releases/TreeletHub-Mac-X.Y.Z.dmg
   ```
3. 更新 `.github/workflows/release-dmg.yml` 中的版本化文件名。
4. 编写 `docs/release-notes-vX.Y.Z.md`（与 tag 同名，如 `v1.2.7` → `release-notes-v1.2.7.md`）。
5. 更新 `README.md` 中的功能说明、版本号与下载链接。
6. 提交并推送 `main`，再打 tag 并推送：
   ```bash
   git add releases/TreeletHub.dmg releases/TreeletHub-Mac-X.Y.Z.dmg \
     docs/release-notes-vX.Y.Z.md README.md .github/workflows/release-dmg.yml
   git commit -m "Release macOS vX.Y.Z DMG"
   git push origin main
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
7. 在 [Actions](https://github.com/shuzhzh/TreeletHub/actions) 确认 workflow 成功；Release 出现在 [Releases](https://github.com/shuzhzh/TreeletHub/releases)。

## README 直链（可选）

若固定文件名为 `TreeletHub.dmg`，可在 README 使用：

`https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg`

（仅当 Release 附件使用该文件名时有效。）

## iOS 二维码

已包含在 `assets/ios-app-qr.png`，并在 `README.md` 中展示。更新二维码时替换该文件并 push 即可。

## 截图（可选）

将宣传截图放入 `assets/screenshots/`，并在 README 中引用，便于 GitHub 仓库首页展示。
