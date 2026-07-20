#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TreeletHub.app"
DMG_NAME="TreeletHub-Mac-1.2.6.dmg"
VOL_NAME="TreeletHub"
# create-dmg 要求：背景图像素尺寸必须与 --window-size 完全一致
WIN_W=660
WIN_H=400
ICON_SIZE=128
APP_X=180
APP_Y=160
APPS_X=480
APPS_Y=160

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/treelet-dmg-staging.XXXXXX")"
BG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/treelet-dmg-bg.XXXXXX")"
BG_RESIZED="${BG_DIR}/background.png"
ICNS="$(mktemp -u "${TMPDIR:-/tmp}/treelet-icon.XXXXXX.icns")"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/treelet-iconset.XXXXXX")/icon.iconset"

cleanup() {
  rm -rf "${STAGING}" "${BG_DIR}" "${ICNS}" 2>/dev/null || true
  rm -rf "$(dirname "${ICONSET}")" 2>/dev/null || true
  rm -f "${ROOT}/rw."*.dmg 2>/dev/null || true
}
trap cleanup EXIT

[[ -d "${ROOT}/${APP_NAME}" ]] || { echo "缺少 ${APP_NAME}" >&2; exit 1; }
[[ -f "${ROOT}/background.png" ]] || { echo "缺少 background.png" >&2; exit 1; }
[[ -f "${ROOT}/logo.png" ]] || { echo "缺少 logo.png" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "请先安装 create-dmg: brew install create-dmg" >&2; exit 1; }

echo "==> 准备 DMG 内容"
cp -R "${ROOT}/${APP_NAME}" "${STAGING}/"
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

OUT_DMG="${ROOT}/${DMG_NAME}"
echo "==> 使用 create-dmg 生成安装包"
rm -f "${OUT_DMG}" "${ROOT}/rw."*.dmg 2>/dev/null || true

# 注意：不使用 --volicon，避免卷内出现 .VolumeIcon.icns；
# 不在 create-dmg 之后再做 hdiutil 二次转换，否则会破坏 .DS_Store 中的背景设置。
create-dmg \
  --volname "${VOL_NAME}" \
  --background "${BG_RESIZED}" \
  --window-size "${WIN_W}" "${WIN_H}" \
  --icon-size "${ICON_SIZE}" \
  --icon "${APP_NAME}" "${APP_X}" "${APP_Y}" \
  --app-drop-link "${APPS_X}" "${APPS_Y}" \
  --hide-extension "${APP_NAME}" \
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
