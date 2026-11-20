#!/usr/bin/env bash
# Create the GitHub repository (GPL-3.0), push `main` and publish the v0.1.0
# release. Requires an authenticated `gh` CLI. Never prints the token.
#
#   REPO=tile-remnant-inventory bash scripts/publish_github.sh
#
# If `gh` is missing / not authenticated the script explains the blocker and
# exits non-zero — it never pretends the push succeeded.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-tile-remnant-inventory}"
TAG="${TAG:-v0.1.0}"
DESCRIPTION="装修瓷砖余料库存与匹配管理 · Flutter + FastAPI"
APK_PATH="${APK_PATH:-$ROOT/dist/tile-remnant-0.1.0.apk}"

cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKED: 未安装 GitHub CLI (gh)。" >&2
  echo "  1) 安装: https://cli.github.com/" >&2
  echo "  2) 认证: gh auth login" >&2
  echo "  3) 重跑: bash scripts/publish_github.sh" >&2
  exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "BLOCKED: gh 未认证。请先执行 'gh auth login'，再重跑本脚本。" >&2
  exit 2
fi

if [ ! -d .git ]; then
  echo "==> git init"
  git init -b main
fi

git add -A
if git diff --cached --quiet; then
  echo "==> 没有待提交的改动"
else
  git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo 'Tile Remnant Bot')}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo 'bot@example.com')}" \
      commit -m "feat: 瓷砖余料库存与匹配管理 v0.1.0"
fi

if git remote get-url origin >/dev/null 2>&1; then
  echo "==> 推送到已有 origin"
  git push -u origin main
else
  echo "==> 创建 GitHub 仓库 $REPO 并推送"
  gh repo create "$REPO" --public --source=. --remote=origin --push --description "$DESCRIPTION"
fi

NOTES_FILE="docs/release-notes-v0.1.0.md"
if [ -f "$APK_PATH" ]; then
  echo "==> 创建 Release $TAG（附 APK）"
  gh release create "$TAG" "$APK_PATH#tile-remnant-0.1.0.apk" \
    --title "v0.1.0 · 首个可运行版本" \
    --notes-file "$NOTES_FILE"
else
  echo "==> 未找到 APK（$APK_PATH），Release 仅附构建说明"
  gh release create "$TAG" \
    --title "v0.1.0 · 首个可运行版本" \
    --notes-file "$NOTES_FILE"
fi

echo "==> 完成: $(gh repo view --json url -q .url)"
