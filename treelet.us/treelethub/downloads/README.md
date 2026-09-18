# Mac 直装包（Cloudflare）

正式下载地址（国内可达）：

**https://models.appda.store/treelethub/TreeletHub.dmg**

| 项 | 值 |
|----|----|
| 公网域名 | `models.appda.store`（Zone：`appda.store`） |
| Worker | `treelet-model-cdn` |
| R2 桶 | `treelet-models` |
| 对象键 | `treelethub/TreeletHub.dmg` |

配置同步：

- App：`TreeletHubShared/HubDownloadURLs.swift` → `macDMG`
- Web 模板：`downloads/urls.js` → `macDmg`（treelet.us 上请把按钮 `href` 改成同一 URL）

## 上传新 DMG

在 `xiaoshuhealth/infra/model-cdn`：

```bash
UPLOAD_TOKEN=xxx node scripts/upload-r2-multipart.mjs \
  --file ./TreeletHub.dmg \
  --key treelethub/TreeletHub.dmg \
  --base https://models.appda.store
```

不要用 `*.workers.dev` 或 GitHub Releases 作为面向中国用户的主下载链。
