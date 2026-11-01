#!/usr/bin/env bash
# 把各 App 的最新 Release APK 同步到服务器，并清掉旧版本。
#
# 用法：
#   bash scripts/sync_app_apks.sh            # 同步
#   bash scripts/sync_app_apks.sh --check    # 只看有哪些更新，不下载
#
# 每个 App 的文件名统一成 `<前缀>-<版本>.apk`（去掉 tag 里的 V 前缀），
# 这样清理旧版时用 `<前缀>-*.apk` 就能精确匹配，不会误删同名前缀的其它 App
# （比如 PinSwipe- 不会匹配到 PinSwipeForGalaxy-）。
set -euo pipefail

cd "$(dirname "$0")/.."

REMOTE="${TILE_HOST:-root@8.134.164.80}"
KEY="${TILE_SSH_KEY:-$HOME/.ssh/id_ed25519_workbuddy}"
REMOTE_DIR="${TILE_DOWNLOAD_DIR:-/opt/apps-archive/downloads}"
TMP="${TMPDIR:-/tmp}/apk-sync"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

mkdir -p "$TMP"

# repo|文件名前缀|是否对外发布
APPS=(
  "tile-remnant-inventory|tile-remnant|yes"
  "qingdou-archive|qingdou|no"
  "EdgePad|edgepad|yes"
  "RuleTree|ruletree|yes"
  "RoutineX|routinex|yes"
  "Curtain|Curtain|yes"
  "PinSwipe|PinSwipe|yes"
  "PinSwipeForGalaxy|PinSwipeForGalaxy|yes"
)

updated=0
skipped=0
failed=0

for entry in "${APPS[@]}"; do
  IFS='|' read -r repo prefix publish <<< "$entry"

  if [ "$publish" = "no" ]; then
    echo "— $repo：不对外发布，确保服务器上没有它的包"
    if [ "$CHECK_ONLY" = "0" ]; then
      ssh -i "$KEY" "$REMOTE" "cd $REMOTE_DIR && rm -f ${prefix}-*.apk 2>/dev/null || true"
    fi
    continue
  fi

  line=$(gh release view --repo "z7ui/$repo" --json tagName,assets \
    -q '.tagName + " " + ([.assets[] | select(.name|endswith(".apk")) | .name] | first)' 2>/dev/null || true)
  tag=${line%% *}
  asset=${line#* }
  if [ -z "$tag" ] || [ "$asset" = "$line" ] || [ -z "$asset" ]; then
    echo "✗ $repo：查不到 Release 或没有 apk 资产"
    failed=$((failed + 1))
    continue
  fi

  ver=$(printf '%s' "$tag" | sed -E 's/^[Vv]//')
  target="${prefix}-${ver}.apk"

  if ssh -i "$KEY" "$REMOTE" "test -f $REMOTE_DIR/$target"; then
    echo "= $repo $ver 已是最新"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$CHECK_ONLY" = "1" ]; then
    echo "↑ $repo 有新版本 $ver（$asset）"
    continue
  fi

  url="https://github.com/z7ui/$repo/releases/download/$tag/$asset"
  echo "↓ $repo $ver 下载中…（$asset）"
  if ! curl -fsSL --noproxy '*' -o "$TMP/$target" "$url"; then
    echo "✗ $repo 下载失败"
    failed=$((failed + 1))
    continue
  fi

  ssh -i "$KEY" "$REMOTE" "cat > $REMOTE_DIR/$target" < "$TMP/$target"
  # 只保留这一版：删除同前缀的其它 apk
  ssh -i "$KEY" "$REMOTE" "cd $REMOTE_DIR && ls -1 ${prefix}-*.apk 2>/dev/null | grep -v '^${target}\$' | xargs -r rm -f"
  size=$(wc -c < "$TMP/$target" | tr -d ' ')
  echo "✓ $repo $ver 已更新（${size} 字节）"
  updated=$((updated + 1))
done

echo
echo "完成：更新 ${updated} 个，已最新 ${skipped} 个，失败 ${failed} 个"
echo "下载页面：https://www.z7ui.cn/apps/"
[ "$updated" -gt 0 ] && echo "提醒：有版本变动时，记得同步更新 docs/software-collection.md 里的版本号和下载链接。"
exit 0
