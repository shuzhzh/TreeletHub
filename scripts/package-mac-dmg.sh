#!/usr/bin/env bash
# 将 macOS 全功能包（scheme TreeletHub_Mac / Release）打成官网与 GitHub 用的 DMG。
# App Store 合规包请用 scheme TreeletHub_Mac_AppStore / configuration AppStore（fastlane mac release）。
# 用法：在项目根目录执行 ./scripts/package-mac-dmg.sh
# 可选环境变量：
#   DERIVED_DATA_PATH — 自定义 DerivedData 目录（默认：项目内 build/DerivedData）
#   SKIP_SIGN=1 — 不做代码签名（仅本地验证构建；分发请使用正常签名）
#   EXTRA_XCODEBUILD_ARGS — 附加传给 xcodebuild 的参数

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${ROOT}/TreeletHub.xcodeproj"
SCHEME="TreeletHub_Mac"
CONFIGURATION="Release"
SDK="macosx"
APP_NAME="TreeletHub.app"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT}/build/DerivedData}"
DIST_DIR="${ROOT}/dist"
STAGING_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/treelet-dmg-staging.XXXXXX")"

cleanup() {
  rm -rf "${STAGING_PARENT}"
}
trap cleanup EXIT

echo "==> DerivedData: ${DERIVED_DATA_PATH}"
mkdir -p "${DIST_DIR}"

XCODE_ARGS=(
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -sdk "${SDK}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  build
)

if [[ "${SKIP_SIGN:-}" == "1" ]]; then
  XCODE_ARGS+=(CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO)
fi

if [[ -n "${EXTRA_XCODEBUILD_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  XCODE_ARGS+=(${EXTRA_XCODEBUILD_ARGS})
fi

echo "==> xcodebuild ${XCODE_ARGS[*]}"
xcodebuild "${XCODE_ARGS[@]}"

APP_BUILT="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}"
if [[ ! -d "${APP_BUILT}" ]]; then
  echo "error: 未找到构建产物: ${APP_BUILT}" >&2
  exit 1
fi

SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_BUILT}/Contents/Info.plist" 2>/dev/null || echo "0")"
BUILD_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_BUILT}/Contents/Info.plist" 2>/dev/null || echo "0")"
DMG_NAME="TreeletHub-${SHORT_VER}-${BUILD_VER}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

cp -R "${APP_BUILT}" "${STAGING_PARENT}/"
ln -sf /Applications "${STAGING_PARENT}/Applications"

echo "==> 创建 DMG: ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "Treelet Hub" \
  -srcfolder "${STAGING_PARENT}" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "${DMG_PATH}"

echo "==> 完成: ${DMG_PATH}"
echo "    提示：对外分发时建议使用 Archive + Developer ID 签名，并执行 notarytool 公证以消除 Gatekeeper 警告。"
