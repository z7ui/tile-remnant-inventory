# v0.1.6 · 检查更新（安装包放在自己的服务器上）

## 新增：关于页的「检查更新」

打开 **项目列表右上角 ⓘ → 版本更新**：

- 显示当前版本 `v0.1.6（构建 7）`
- 点「检查更新」，从 `https://www.z7ui.cn/tile-api/apk/version.json` 拉清单
- 有新版时显示：新版本号、安装包大小、更新说明，并出现「下载安装」按钮
- 点「下载安装」交给**系统浏览器**下载，下完点通知栏即可安装

**为什么用浏览器而不是应用内下载**：应用内下载要自己处理存储权限、断点续传、
Android 7+ 的 FileProvider，以及 targetSdk 35 下的「安装未知应用」授权弹窗。
交给系统浏览器，这些全都省了，且用户能看到下载进度。

判断依据是 `versionCode`（构建号），不是版本号字符串——否则 `0.1.10` 会被判成比 `0.1.9` 旧。

## 安装包在自己服务器上

```
https://www.z7ui.cn/tile-api/apk/tile-remnant-0.1.6.apk
https://www.z7ui.cn/tile-api/apk/version.json
```

nginx 直接发静态文件（`location /tile-api/apk/` → `alias /var/www/tile-api/`），
不经过 FastAPI，也不依赖 GitHub。App 只认这个地址。

发布新版本的流程（`scripts/publish_apk_update.sh`）：

```bash
TILE_NOTES="这次改了什么" bash scripts/publish_apk_update.sh
```

脚本会从 APK 里读真实版本号（`aapt2 dump badging`）、算 sha256、生成 `version.json`、
上传 APK 和清单到服务器。

## 改成正式签名

之前所有包都是 **debug 签名**，只能自己装，长期分发会有问题（换机器/重装后签名不一致无法覆盖升级）。
这一版开始用自己生成的 keystore：

```
Signer DN: CN=Tile Remnant, OU=Mobile, O=z7ui, L=Shanghai, ST=Shanghai, C=CN
证书 SHA-256: 407cae1feb81490c5677dded5290b691c9a24cde897425650de37eb93308dafb
```

- keystore 在 `D:/flutte/keystore/tile-upload.jks`，密码在同目录 `PASSWORD.txt`
- `mobile/android/key.properties` 引用它（已在 `.gitignore`，不会进仓库）
- **这个文件务必自己再备份一份**。丢了以后就再也无法覆盖升级，只能让用户卸载重装

> ⚠️ 签名变了，所以**必须卸载旧版再装**这一个。之后版本可以正常覆盖升级。

## 顺带还清三笔技术债

### 1. 工具链版本对齐（之前靠 skip 开关硬撑）

加 `url_launcher` 时踩到：它带进来的 `androidx.core:core:1.17.0` 要求 **AGP ≥ 8.9.1**，
而项目一直是 8.5.2，靠 `--android-skip-build-dependency-validation` 跑。

| 项 | 之前 | 现在 |
| --- | --- | --- |
| AGP | 8.5.2 | **8.11.1** |
| Kotlin | 1.9.24 | **2.2.20** |
| compileSdk | 35 | **36** |
| `--android-skip-build-dependency-validation` | 必须带 | **不需要了** |
| NDK | 靠自动下载，经常失败 | **锁成已装的 28.2.13676358** |

Gradle 8.14.3 / JDK 17 不变，`targetSdk` 仍保持 35（不改变运行时行为）。

### 2. `withOpacity` 弃用

Flutter 3.27 起 `Color.withOpacity` 被弃用（会有精度损失），3.47 里 analyze 一直报。
25 处全部换成 `withValues(alpha: ...)`，analyze 从 64 条降到 38 条。
剩下的是 `prefer_const` 之类的风格建议，不影响构建。

### 3. 部署方式与文档一致

之前 README 写 Docker、实际用 systemd，已经统一（v0.1.1 那轮做的）。

## 验证

- `flutter analyze`：0 error，38 条 info
- `apksigner verify`：正式证书，DN 如上
- 服务端：`version.json` 返回 `application/json`，APK 返回
  `application/vnd.android.package-archive`，博客未受影响

版本 0.1.6+7。
