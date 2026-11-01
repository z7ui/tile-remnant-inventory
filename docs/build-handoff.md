# 编译「余砖管家」交接说明（给接手的 AI）

> 目标：拿到源码后，在本机把「余砖管家」编译成可发布的 release APK，并走完发布闭环。
> 本机环境已全部就位，**无需重新安装任何工具**，照着做即可。

## 一、编译的是哪个项目

- 源码根目录：`C:\Users\z7ui\WorkBuddy\2026-10-31-20-29-25\tile-remnant-inventory\`
- 要编译的是**移动端 APK**：`mobile/`（Flutter 项目）
- `backend/` 是 FastAPI 后端，**编译 APK 不涉及它**（App 运行时才连后端；后端部署见 `README.md` 第八/九章）

## 二、编译需要什么（都在本机，路径如下）

| 依赖 | 位置 | 备注 |
| --- | --- | --- |
| Flutter SDK | `D:/flutte/flutter` | 版本 3.47.9 |
| JDK 17 | `D:/flutte/jdk-17.0.20.1+1` | Temurin 17.0.20.1；Gradle 8.7 只支持到 JDK 21，**必须用 17** |
| Android SDK | `C:\Users\z7ui\AppData\Local\Android\Sdk` | 已装 platform 34/35/36/37 + build-tools 34/35/36 |
| Gradle 8.7 离线包 | `D:/flutte/gradle-dist/gradle-8.7-all.zip` | 网络下不动 gradle 时用（见「常见坑」） |
| 签名密钥 | `D:/flutte/keystore/tile-upload.jks` | 别名 `tile-upload` |

签名口令在 `D:/flutte/keystore/PASSWORD.txt` 与 `mobile/android/key.properties`，**均已就位，
构建脚本自动读取，无需手动处理**。不要把口令写进任何公开文件或 git 仓库。

> 密钥文件本身不在项目里（`.gitignore` 已排除）。服务器 `/opt/apps-archive/signing/`
> 有加密的第二份，换机器时按 `docs/signing-backup.md` 恢复。

## 三、怎么编译（一条命令）

```bash
cd C:/Users/z7ui/WorkBuddy/2026-10-31-20-29-25/tile-remnant-inventory
API_BASE_URL=https://www.z7ui.cn/tile-api bash scripts/build_apk.sh
```

产物：`dist/tile-remnant-<版本>.apk`

脚本自动完成：生成 `android/local.properties` → 补 Gradle wrapper → `pub get` →
`analyze` → `test` → `build apk --release`（只打 arm64）。

> ⚠️ **必须显式传 `API_BASE_URL`**。脚本默认值是占位符 `https://tiles.example.com`，
> 不传会构建出连到错误地址的包。正式地址固定 `https://www.z7ui.cn/tile-api`。

## 四、编译完做什么（发布闭环，按顺序）

1. **升版本号**（改了代码就必做）：改 `mobile/pubspec.yaml` 的 `version:`，例如
   `0.1.23+24` → `0.1.24+25`（`+` 后是 versionCode，必须递增）。
   否则同版本号但内容不同 → 同名 APK 哈希不同，用户和分发渠道分不清哪个最新，
   且 versionCode 不递增会被系统拒绝同版本覆盖。
2. **发到服务器**（App 内「检查更新」依赖它）：
   ```bash
   TILE_NOTES="本次更新说明" bash scripts/publish_apk_update.sh
   ```
   会把 APK 传到服务器 `/var/www/tile-api/`，改写 `version.json`，并清掉旧版本。
3. **发 GitHub Release**（用 `gh`，需已 `gh auth login`）：建新 tag、附 APK、写 release notes
   （模板参考 `docs/release-notes-v*.md`）。
4. **同步下载页**：
   ```bash
   bash scripts/sync_app_apks.sh
   ```
   把最新 Release APK 同步到服务器 `/opt/apps-archive/downloads/`，下载页 `z7ui.cn/apps/` 生效。
5. **更新博客软件合集**：改了版本号就同步 `docs/software-collection.md` 里的版本和下载链接，
   再发布到 z7ui.cn（方法见 `docs/software-collection-maintenance.md`）。

## 五、常见坑（`README.md` 第十章也有，这里摘要）

- `Java/Gradle incompatibility`（提示 Java 25）→ 必须 `flutter config --jdk-dir="D:/flutte/jdk-17.0.20.1+1"`，
  **只设 `JAVA_HOME` 不生效**（Flutter 有自己的 jdk 配置）。
- `Downloading gradle-8.7-all.zip failed: timeout` → 用本地包：把 `mobile/android/gradle/wrapper/gradle-wrapper.properties`
  的 `distributionUrl` 临时指向 `file:///D:/flutte/gradle-dist/gradle-8.7-all.zip`。
- `flutter test` 报 `Invalid WebSocket upgrade request` → 清掉 `http_proxy`/`https_proxy`，
  并设 `NO_PROXY=localhost,127.0.0.1,::1`。

## 六、当前版本状态

- `mobile/pubspec.yaml` 当前是 `0.1.23+24`；
- `dist/` 里最新已发布的是 `0.1.22`，即 **0.1.23 已升版本号、但还没构建/发布**。
