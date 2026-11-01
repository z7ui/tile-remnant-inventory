#!/usr/bin/env bash
# 把构建好的 APK 发到自己的服务器，并改写 version.json，
# 让 App 里「关于 → 检查更新」能发现新版本。
#
# 用法：
#   bash scripts/publish_apk_update.sh                        # 用默认路径的 APK
#   bash scripts/publish_apk_update.sh dist/xxx.apk           # 指定 APK
#   TILE_NOTES="修复了xx" bash scripts/publish_apk_update.sh   # 带更新说明
#
# 环境变量：
#   TILE_HOST        默认 root@8.134.164.80
#   TILE_SSH_KEY     默认 ~/.ssh/id_ed25519_workbuddy
#   TILE_PUBLIC_BASE 默认 https://www.z7ui.cn/tile-api
#   TILE_REMOTE_DIR  默认 /var/www/tile-api
set -euo pipefail

cd "$(dirname "$0")/.."

APK="${1:-mobile/build/app/outputs/flutter-apk/app-release.apk}"
HOST="${TILE_HOST:-root@8.134.164.80}"
KEY="${TILE_SSH_KEY:-$HOME/.ssh/id_ed25519_workbuddy}"
REMOTE_DIR="${TILE_REMOTE_DIR:-/var/www/tile-api}"
PUBLIC_BASE="${TILE_PUBLIC_BASE:-https://www.z7ui.cn/tile-api}"
NOTES="${TILE_NOTES:-}"

[ -f "$APK" ] || { echo "找不到 APK: $APK（先跑 flutter build apk --release）" >&2; exit 1; }

# 版本号从 APK 本身读，避免和 pubspec 不同步
AAPT="${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}/build-tools/36.0.0/aapt2.exe"
if [ ! -x "$AAPT" ]; then
  AAPT="$(ls -d "${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}"/build-tools/*/aapt2.exe 2>/dev/null | tail -1 || true)"
fi
[ -n "${AAPT:-}" ] && [ -x "$AAPT" ] || { echo "找不到 aapt2，无法读取版本号" >&2; exit 1; }

BADGING=$("$AAPT" dump badging "$APK" 2>/dev/null | head -1)
VERSION=$(printf '%s' "$BADGING" | sed -nE "s/.*versionName='([^']+)'.*/\1/p")
CODE=$(printf '%s' "$BADGING" | sed -nE "s/.*versionCode='([^']+)'.*/\1/p")
[ -n "$VERSION" ] && [ -n "$CODE" ] || { echo "解析版本号失败" >&2; exit 1; }

NAME="tile-remnant-${VERSION}.apk"
SIZE=$(wc -c < "$APK" | tr -d ' ')
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# notes 里可能有引号，做一次最小转义
NOTES_JSON=$(printf '%s' "$NOTES" | sed 's/\\/\\\\/g; s/"/\\"/g')

JSON=$(cat <<EOF
{
  "version": "${VERSION}",
  "versionCode": ${CODE},
  "apk": "${NAME}",
  "apk_url": "${PUBLIC_BASE}/apk/${NAME}",
  "size": ${SIZE},
  "sha256": "${SHA}",
  "notes": "${NOTES_JSON}",
  "publishedAt": "${STAMP}"
}
EOF
)

echo "==> 版本 ${VERSION} (${CODE})、${SIZE} 字节"
ssh -i "$KEY" "$HOST" "mkdir -p ${REMOTE_DIR}"
ssh -i "$KEY" "$HOST" "cat > ${REMOTE_DIR}/${NAME}" < "$APK"
printf '%s\n' "$JSON" | ssh -i "$KEY" "$HOST" "cat > ${REMOTE_DIR}/version.json && chmod 644 ${REMOTE_DIR}/*"

# 只留最新一版：旧包既占空间，也容易让人从目录列表里下错版本。
# 按修改时间排序，除第一个全删。
ssh -i "$KEY" "$HOST" "cd ${REMOTE_DIR} && ls -1t tile-remnant-*.apk 2>/dev/null | tail -n +2 | xargs -r rm -f"
echo "==> 旧版本已清理，只保留 ${NAME}"

echo "==> 已发布：${PUBLIC_BASE}/apk/${NAME}"
echo "==> 清单：  ${PUBLIC_BASE}/apk/version.json"
