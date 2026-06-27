# 小树应用官网 · Treelet Website

## 📁 结构说明

- **`index.html`** — 首页：App 选择页。第一项为 **小树中医**，第二项为 **小树健康**。点击小树健康会根据浏览器语言跳转：
  - 中文 → https://treelethealth.com/zh/index.html  
  - 非中文 → https://treelethealth.com/en/index.html  

- **`tcm/index.html`** — 小树中医站点页
  - 自动检测浏览器语言：非中文环境默认英文，否则中文
  - 支持中/英切换，文案来自 `tcm/i18n.json` 键值
  - 功能介绍与 TreeletTCM iOS 应用一致：健康概览、脉象分析、体质分析、舌象自测、脏腑辨证、今日建议、养生与时辰等

- **`assets/`** — 图片资源（来自 TreeletTCM 项目）
  - `tcm-icon.png` — 小树中医 App 图标
  - `tcm-logo.png` — 小树中医 Logo

- **`robots.txt`** — 爬虫规则，允许全站并指向 sitemap  
- **`sitemap.xml`** — 站点地图，包含首页与 TCM 页的中英交替链接，便于 SEO

## 🌐 语言与 SEO

- 小树中医页：`hreflang` 指向 `?lang=zh` / `?lang=en`，利于搜索引擎区分中英文
- 首页与 TCM 页已设置 `title`、`description`、`keywords`、`og:*`、`twitter:*` 及 JSON-LD 结构化数据
- 部署时请将域名替换为实际域名（例如将 `treelettcm.com` 改为你的域名）

## 🚀 本地预览

用任意静态服务器打开根目录即可，例如：

```bash
cd website
python3 -m http.server 8080
# 或 npx serve .
```

浏览器访问：`http://localhost:8080/`

## 📱 小树健康跳转逻辑（首页）

- 根据 `navigator.language` / `navigator.userLanguage` 判断是否为中文
- 若为中文 → 小树健康链接指向 `https://treelethealth.com/zh/index.html`
- 若非中文 → 指向 `https://treelethealth.com/en/index.html`
