#!/usr/bin/env bash
# Build a release APK for private distribution (no Play Store upload).
#
#   API_BASE_URL=https://tiles.example.com bash scripts/build_apk.sh
#
# Optional release signing (recommended):
#   mobile/android/key.properties with
#     storePassword=...
#     keyPassword=...
#     keyAlias=upload
#     storeFile=/absolute/path/to/upload-keystore.jks
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="$ROOT/mobile"
VERSION="$(grep -m1 '^version:' "$MOBILE/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"
API_BASE_URL="${API_BASE_URL:-https://tiles.example.com}"
OUT_DIR="$ROOT/dist"
APK_NAME="tile-remnant-${VERSION}.apk"

echo "==> 项目目录: $ROOT"
echo "==> API_BASE_URL=$API_BASE_URL"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 未找到 Flutter SDK。请安装 Flutter 3.22+ 并把 flutter 加入 PATH。" >&2
  echo "       参考 README.md 的「构建 APK」章节。" >&2
  exit 1
fi

cd "$MOBILE"

# local.properties tells Gradle where the Flutter SDK lives.
if [ ! -f android/local.properties ]; then
  FLUTTER_BIN="$(command -v flutter)"
  FLUTTER_SDK="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
  printf 'flutter.sdk=%s\nsdk.dir=%s\n' "$FLUTTER_SDK" "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}" > android/local.properties
  echo "==> 已生成 android/local.properties"
fi

# The Gradle wrapper jar is a binary and is not committed.
if [ ! -f android/gradle/wrapper/gradle-wrapper.jar ]; then
  if command -v gradle >/dev/null 2>&1; then
    echo "==> 生成 Gradle wrapper"
    (cd android && gradle wrapper --gradle-version 8.7 --distribution-type all)
  else
    echo "ERROR: 缺少 android/gradle/wrapper/gradle-wrapper.jar 且未安装 gradle。" >&2
    echo "       解决方式（任选其一）:" >&2
    echo "         a) 安装 Gradle 8.7 后重跑本脚本" >&2
    echo "         b) 在 mobile/ 下执行: flutter create --platforms=android --project-name tile_remnant ." >&2
    exit 1
  fi
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter analyze"
flutter analyze --no-fatal-infos

echo "==> flutter test"
flutter test

# Gradle 8.7 只支持到 JDK 21。Flutter 默认会挑 Android Studio 自带的 JDK，
# 那可能是 25，于是直接报 "Java/Gradle incompatibility" —— 而且只设 JAVA_HOME 不生效，
# 必须用 `flutter config --jdk-dir=`。这里提前提醒一句，省得编译到一半才发现。
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  _jv="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
  if [ "${_jv:-0}" -ge 22 ] 2>/dev/null; then
    echo "WARN: JAVA_HOME 指向 JDK $_jv，而 Gradle 8.7 只支持到 21。"
    echo "      如果构建报 Java/Gradle incompatibility，执行下面这行后重试："
    echo "        flutter config --jdk-dir=<JDK 17 的安装路径>"
  fi
fi

echo "==> flutter build apk --release"
flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --target-platform android-arm64

mkdir -p "$OUT_DIR"
cp "build/app/outputs/flutter-apk/app-release.apk" "$OUT_DIR/$APK_NAME"
echo "==> APK: $OUT_DIR/$APK_NAME"
ls -lh "$OUT_DIR/$APK_NAME"
