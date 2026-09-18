#!/usr/bin/env bash
# TreeletHub fancy DMG packager. Agent workflow: skill `package-mac-dmg`
# (see .cursor/skills/package-mac-dmg/SKILL.md). Do not add post-create-dmg remounts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.3.0}"
# 卷内始终使用 TreeletHub.app，源目录可以是导出的带版本号目录
APP_NAME="TreeletHub.app"
APP_SRC="${ROOT}/TreeletHub-Mac-${VERSION}.app"
[[ -d "${APP_SRC}" ]] || APP_SRC="${ROOT}/${APP_NAME}"
DMG_NAME="TreeletHub-Mac-${VERSION}.dmg"
VOL_NAME="TreeletHub"
# create-dmg 要求：背景图像素尺寸必须与 --window-size 完全一致
WIN_W=660
WIN_H=400
ICON_SIZE=128
# 左侧 App、右侧 Applications（与背景图布局对齐）
APP_X=180
APP_Y=160
APPS_X=480
APPS_Y=160

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/treelet-dmg-staging.XXXXXX")"
BG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/treelet-dmg-bg.XXXXXX")"
BG_RESIZED="${BG_DIR}/background.png"
ICNS="$(mktemp -u "${TMPDIR:-/tmp}/treelet-icon.XXXXXX.icns")"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/treelet-iconset.XXXXXX")/icon.iconset"

CDMG_SUPPORT="$(brew --prefix create-dmg)/share/create-dmg/support"
CDMG_BIN="$(brew --prefix create-dmg)/bin/create-dmg"
CDMG_VENDOR="$(mktemp -d)/create-dmg-vendor"

cleanup() {
  rm -rf "${STAGING}" "${BG_DIR}" "${ICNS}" "${CDMG_VENDOR}" 2>/dev/null || true
  rm -rf "$(dirname "${ICONSET}")" 2>/dev/null || true
  rm -f "${ROOT}/rw."*.dmg 2>/dev/null || true
}
trap cleanup EXIT

[[ -d "${APP_SRC}" ]] || { echo "缺少 app 包: ${APP_SRC}" >&2; exit 1; }
[[ -f "${ROOT}/background.png" ]] || { echo "缺少 background.png" >&2; exit 1; }
[[ -f "${ROOT}/logo.png" ]] || { echo "缺少 logo.png" >&2; exit 1; }
[[ -f "${ROOT}/dmg-support/template.applescript" ]] || { echo "缺少 dmg-support/template.applescript" >&2; exit 1; }
[[ -f "${ROOT}/dmg-support/DS_Store" ]] || { echo "缺少 dmg-support/DS_Store" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "请先安装 create-dmg: brew install create-dmg" >&2; exit 1; }

echo "==> 准备 DMG 内容（源: $(basename "${APP_SRC}")）"
cp -R "${APP_SRC}" "${STAGING}/${APP_NAME}"
# 背景图缩放到与窗口同尺寸（create-dmg 硬性要求）
sips -z "${WIN_H}" "${WIN_W}" "${ROOT}/background.png" --out "${BG_RESIZED}" >/dev/null

mkdir -p "${ICONSET}"
echo "==> 生成 logo.icns（仅用于 .dmg 文件图标）"
sips -z 16 16 "${ROOT}/logo.png" --out "${ICONSET}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ROOT}/logo.png" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ROOT}/logo.png" --out "${ICONSET}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ROOT}/logo.png" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ROOT}/logo.png" --out "${ICONSET}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ROOT}/logo.png" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ROOT}/logo.png" --out "${ICONSET}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ROOT}/logo.png" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ROOT}/logo.png" --out "${ICONSET}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ROOT}/logo.png" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null
iconutil -c icns "${ICONSET}" -o "${ICNS}"

echo "==> 准备 create-dmg  vendor（自定义 Finder 模板）"
mkdir -p "${CDMG_VENDOR}/support"
touch "${CDMG_VENDOR}/.this-is-the-create-dmg-repo"
cp "${CDMG_BIN}" "${CDMG_VENDOR}/create-dmg"
cp -R "${CDMG_SUPPORT}/." "${CDMG_VENDOR}/support/"
cp "${ROOT}/dmg-support/template.applescript" "${CDMG_VENDOR}/support/template.applescript"
chmod u+w "${CDMG_VENDOR}/create-dmg"
chmod +x "${CDMG_VENDOR}/create-dmg"
# 当前 macOS Finder 的 AppleScript 不再把 backgroundImageAlias 写入 .DS_Store。
# 在 convert 之前装入已验证的布局文件，避免二次转换破坏背景。
python3 - "${CDMG_VENDOR}/create-dmg" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
needle = 'echo "Fixing permissions..."'
insert = """
if [[ -n "${TREELETHUB_DS_STORE:-}" && -f "${TREELETHUB_DS_STORE}" ]]; then
  echo "Installing Finder .DS_Store for background and icon layout"
  cp "${TREELETHUB_DS_STORE}" "${MOUNT_DIR}/.DS_Store"
fi

"""
if needle not in text:
    raise SystemExit("create-dmg 脚本缺少 Fixing permissions 锚点，无法注入 .DS_Store")
path.write_text(text.replace(needle, insert + needle, 1))
PY
CREATE_DMG_RUN="${CDMG_VENDOR}/create-dmg"
export TREELETHUB_DS_STORE="${ROOT}/dmg-support/DS_Store"

OUT_DMG="${ROOT}/${DMG_NAME}"
echo "==> 使用 create-dmg 生成安装包"
rm -f "${OUT_DMG}" "${ROOT}/rw."*.dmg 2>/dev/null || true

# 注意：不使用 --volicon，避免卷内出现 .VolumeIcon.icns；
# 不在 create-dmg 之后再做 hdiutil 二次转换，否则会破坏 .DS_Store 中的背景设置。
"${CREATE_DMG_RUN}" \
  --volname "${VOL_NAME}" \
  --background "${BG_RESIZED}" \
  --window-size "${WIN_W}" "${WIN_H}" \
  --icon-size "${ICON_SIZE}" \
  --icon "${APP_NAME}" "${APP_X}" "${APP_Y}" \
  --app-drop-link "${APPS_X}" "${APPS_Y}" \
  --hide-extension "${APP_NAME}" \
  --skip-jenkins \
  --bless \
  --no-internet-enable \
  --format UDZO \
  "${OUT_DMG}" \
  "${STAGING}"

echo "==> 设置 DMG 文件图标"
/usr/bin/swift - <<SWIFT
import AppKit
let logo = "${ROOT}/logo.png"
let dmg = "${OUT_DMG}"
guard let image = NSImage(contentsOfFile: logo) else {
  fputs("无法读取 logo.png\n", stderr)
  exit(1)
}
NSWorkspace.shared.setIcon(image, forFile: dmg, options: [])
SWIFT

echo "==> 完成: ${OUT_DMG}"
ls -lh "${OUT_DMG}"
