# v0.1.1 · 服务器地址写死进安装包

## 为什么有这一版

v0.1.0 的 APK 里，服务器地址是编译时默认的占位符 `https://tiles.example.com`——
装上之后连不上任何后端，等于废包。这一版把地址写死成实际部署的地址，装完就能用。

## 服务器地址现在跟着安装包走

```
https://www.z7ui.cn/tile-api
```

- 编译期注入：`--dart-define=API_BASE_URL=https://www.z7ui.cn/tile-api`
- **Release 包不允许运行时改地址**（`AppConfig.serverLocked`）：
  - 项目列表页的「服务器与同步设置」图标不再显示
  - 加入项目页的服务器只读，「修改」按钮不显示
  - 启动失败页的「修改服务器地址」换成一句提示
  - `Session.setServer()` 在 release 下直接抛错（入口漏判时的双保险）
  - 首次启动会清掉本地存的旧地址；如果旧地址与编译值不同，连设备身份和项目列表一起清
    （那些是旧服务器签发的，带过来只会 401）
- debug 构建仍可改，方便连本机调试

**为什么不允许改**：这个 App 没有账号体系，设备身份（设备 ID + 密钥）是发给「服务器」的。
地址能在界面上随便填，就等于留了一条把设备密钥骗到第三方服务器的路。地址跟安装包绑定，
要换地址只能换安装包。

## 后端

部署在 `https://www.z7ui.cn/tile-api`，**systemd + 宿主机 nginx 反代**（不是 Docker，
机器上已有博客的 nginx 占着 80/443）：

```
GET https://www.z7ui.cn/tile-api/healthz
→ 200 {"status":"ok","version":"0.1.1","time":"..."}
```

- 服务只监听 `127.0.0.1:8000`，外部一律走 nginx
- 数据在 `/var/lib/tile/tile_remnant.db`
- 未认证访问 `/tile-api/api/projects` 返回 `401`

## 安装

`tile-remnant-0.1.1.apk` · arm64 · minSdk 24 · targetSdk 35 · **debug 签名**（能装能跑，
不适合长期分发）。

## 已知问题

- 没有 keystore，签名是 debug 的；正式分发前要生成
- AGP 仍是 8.5.2，靠 `--android-skip-build-dependency-validation` 在 Flutter 3.47.9 上打包
