# 怎么用

分两种人写：

- **只想用**（装修业主、师傅）：看第一节，装个 APK 就能开工。
- **想自己跑 / 改代码 / 打包**：从第二节开始，环境要求和踩过的坑都写在里面了。

---

## 一、手机上用

### 1.1 装 APK

从项目的 Release 页下 `tile-remnant-0.1.0.apk`，用文件管理器打开安装（首次要允许「安装未知应用」）。

> 只打了 **arm64** 一种架构——2020 年以后的安卓手机基本都是 arm64，老机器装不上。

### 1.2 第一次打开

App 不注册账号，第一次启动会**自己注册这台设备**（设备 ID + 密钥，密钥只发一次，存在手机的安全存储里）。

服务器地址是**打包时注入**的（`--dart-define=API_BASE_URL=...`）。要换服务器：项目列表页右上角「更换服务器？」。

### 1.3 建项目，或者加入别人的

- **自己开工**：「新建项目」→ 填项目名 + 选单位（毫米 / 厘米）。项目名是**全局唯一**的，用来区分不同工地；连删掉的项目也占着名字，改名得换一个。
- **别人拉你**：扫他给的二维码，或手输 10 位邀请码。

### 1.4 入库：手上是灰也能三步录完

底部「库存」→ 新增。

1. 长、宽：直接输数字按项目默认单位算；也可以带单位（`80cm`、`800mm`），甚至小数（`80.5cm`）。中间别加空格——`8 0` 会被当成错误，这是故意的。
2. 片数：这一批有几片。
3. 可选的「存放位置」（阳台左边、次卧衣柜顶）和「备注」（色号、批次）——**建议填**，三个月后全靠这两个字段找砖。

点「确认入库」。

> 只支持**矩形**。L 形、异形砖在入库这一步是存不进来的，它们是**切出来的余料**，走 1.6。
> 单位内部一律存整数毫米，显示时再按项目单位换算。

### 1.5 匹配：说「要 800×600」，它告诉你切哪块

底部「匹配」→「需要多大」填需求尺寸 →「开始匹配」。

- 自动允许**旋转 90°**，长短边不用自己理清；
- 需求必须被余砖**完全覆盖**，盖不住的不给候选（不会给你一个差 2 厘米的方案）；
- 每张候选卡写着：原砖尺寸、**浪费**多少、剩几片、切完的余料是**矩形还是 L 形**；
- 点「旋转 90°」能换另一种摆法，浪费量会跟着变。

### 1.6 切割：余料要么入库要么丢弃，但都得记账

点中一张候选 → 确认页。

1. 选切法：**长边切到底** / **短边切到底**（两种切法对应四种余料结果，页面上有实时图示：原砖、需求、余料各是什么样）。
2. 余料怎么处理：
   - **直接入库**：余料变成一条新库存（矩形或 L 形都行），下次还能用它；
   - **丢弃**：库存不增加，但**照样写流水**——账要留住，砖可以不要。
3. 确认。原砖的片数减 1，新库存和流水同时生成。

> 这一步是并发安全的：两个手机同时确认同一块砖，不会超扣；网络不好重复点，也不会重复扣（幂等键）。

### 1.7 三个月后：这块砖哪来的

两种入口：库存卡片点进去，或者流水里点「溯源」。

溯源页三列并排：**原砖 / 当时的切割需求 / 切出来的余料**，下面还有父子链（这块砖是从哪块砖切出来的、又切出了什么）和全部关联流水。一路往上能追到最初入库的那一批。

### 1.8 几个人一起用

项目设置里生成**邀请码**（10 位、长期有效、可随时撤销或重置）。对方「扫码加入」或手输即可，加入后共享同一份库存和流水。

邀请码可以撤销——人走了就撤掉，旧码立刻失效。

### 1.9 导出台账

「流水」页 → 导出 CSV。文件带 BOM，Excel 双击直接打开，中文表头不乱码。

---

## 二、本机跑后端

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate   /   macOS·Linux: source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

打开 <http://127.0.0.1:8000/docs> 就是接口文档（开发模式默认开，生产环境关）。

默认配置（`app/config.py`）：SQLite `./data/tile_remnant.db`、自动建表、`environment=development`。要换数据库设 `DATABASE_URL`。

跑测试：

```bash
cd backend && python -m pytest -q      # 104 passed
```

> **pip 装不上包时**：如果配了国内镜像却报 `No matching distribution found`（`from versions: none`），
> 换成官方源再试一次，多数时候就好了：
> `pip install --index-url https://pypi.org/simple -r requirements.txt`

---

## 三、构建 APK

### 3.1 环境要求（这三样缺一不可）

| 组件 | 版本 | 说明 |
|---|---|---|
| Flutter | 3.22+ | 实际用 3.47.9（Dart 3.13.7）验证 |
| **JDK** | **17** | **不能是 25**：Gradle 8.7 不支持，会直接报 `Java/Gradle incompatibility` |
| Android SDK | build-tools 34+ | 有 `platform-tools`、`build-tools`、`licenses` 就够 |
| Gradle | 8.7 | 由 wrapper 自动下，不用手装 |

### 3.2 三条命令

```bash
# 1. 指定 JDK（Flutter 有自己的一份 jdk 配置，光设 JAVA_HOME 不管用）
flutter config --jdk-dir="D:\flutte\jdk-17.0.20.1+1"

# 2. 构建（API_BASE_URL 换成你自己后端的地址）
cd mobile
flutter build apk --release \
  --dart-define=API_BASE_URL=https://你的域名 \
  --target-platform android-arm64

# 3. 产物
#    mobile/build/app/outputs/flutter-apk/app-release.apk
```

或者用封装好的脚本（会顺带跑 analyze + test，产物复制到 `dist/`）：

```bash
API_BASE_URL=https://你的域名 bash scripts/build_apk.sh
# → dist/tile-remnant-0.1.0.apk
```

### 3.3 真机上踩过的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| `The Flutter directory is not a clone of the GitHub project` | SDK 解压时丢了 `.git`（zip 里的隐藏目录没跟着走） | 重新解压完整 zip；或 `git init` 后 `git add -A && git commit`，再 `git tag 3.47.9`，并把 `bin/cache/flutter_tools.stamp` 写成 `"$(git rev-parse HEAD):"` |
| `Unable to update Dart SDK` / engine hash 是 `e69de29` | 同上，`bin/internal/engine.version` 没被 git 跟踪，脚本读不到 | 同上，确保 `git ls-files bin/internal/engine.version` 有输出 |
| `dart.exe` 不存在，但 `bin/cache` 里躺着 `dart-sdk.old1` | 上次下载中断，旧 SDK 被改名了 | 删掉空的 `dart-sdk`，把 `dart-sdk.old1` 改回 `dart-sdk` |
| `Downloading ... gradle-8.7-all.zip failed: timeout` | `services.gradle.org` 国内经常连不上 | 下腾讯镜像 `https://mirrors.cloud.tencent.com/gradle/gradle-8.7-all.zip`，把 `gradle-wrapper.properties` 的 `distributionUrl` 临时指向本地文件：`file\:///D\:/路径/gradle-8.7-all.zip` |
| `Java/Gradle incompatibility`，提示 Java 25 | Flutter 自带了 Android Studio 的 JDK 25 | `flutter config --jdk-dir=<JDK17 路径>`（**只设 JAVA_HOME 不生效**） |
| `Invalid WebSocket upgrade request`（跑 `flutter test` 时） | 系统代理拦了 localhost 的 WebSocket | 清掉 `http_proxy/https_proxy`，并设 `NO_PROXY=localhost,127.0.0.1,::1` |
| `flutter doctor` 报 `reg query` 失败 | 沙箱/安全策略禁止 `reg.exe` | 不影响构建，忽略（连的是 Windows Version / Edge 检测） |

### 3.4 签名

默认用 debug 签名，能装能跑。要正式签名，在 `mobile/android/key.properties` 里写：

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

---

## 四、部署到自己的服务器

```bash
cp .env.example .env
# 必改：PUBLIC_BASE_URL=https://你的域名、DATABASE_URL、POSTGRES_PASSWORD（用 pg 时）
docker compose up -d --build
```

- 只暴露 nginx 的 80/443，**API 和数据库都不映射到宿主机**；
- 证书放 `deploy/certs/`（`fullchain.pem` + `privkey.pem`）；
- 要 PostgreSQL：`docker compose --profile postgres up -d`，再把 `DATABASE_URL` 换成 `postgresql+psycopg://...`；
- 健康检查打的是 `/healthz`，返回 `{"status":"ok"}` 才算起来了。

详细步骤见 [`docs/deployment.md`](deployment.md)。

---

## 五、常见问题

**Q：为什么只支持矩形入库？**
切之前你手上就是整砖，矩形是唯一确定的形状；异形只可能来自切割，所以放在「余料」那一步处理。

**Q：切完余料面积对不上？**
L 形余料用「矩形并集」建模（外框减掉缺角），不是多边形布尔运算。面积守恒在 `tests/test_geometry.py` 里有断言。

**Q：换手机了怎么办？**
新设备会重新注册，拿到新身份；用邀请码重新加入项目即可。旧设备可以留着，也可以让管理员撤销邀请码。

**Q：数据存在哪？**
服务器的一个 SQLite 文件（`/data/tile_remnant.db`，WAL 模式），或者你自己接的 PostgreSQL。备份见 [`docs/backup-restore.md`](backup-restore.md)。

**Q：能不能不联网用？**
不能。这是「多人共享一份库存」的工具，必须连服务器。
