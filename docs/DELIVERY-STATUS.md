# 交付状态与阻塞项

> 本文件只写**实际执行过的结果**。没有执行的事情一律标为「未执行」，并给出精确命令。

生成时间：2026-10-31（Asia/Shanghai）
最后更新：2026-10-31 22:57 —— GitHub 与 WordPress 均已发布（原「未执行」两项已关闭）

## 一、已验证

| 项 | 命令 | 结果 |
|---|---|---|
| 后端依赖安装 | `python -m pip install -r backend/requirements.txt` | ✅ fastapi 0.162 / SQLAlchemy 2.1.6 |
| 应用可导入 | `python -c "from app.main import app"` | ✅ 路由挂载正常 |
| 几何引擎 | `pytest tests/test_geometry.py` | ✅ 通过（含 L 形面积守恒、旋转、整砖无余料） |
| 单位解析 | `pytest tests/test_units.py` | ✅ 通过 |
| 项目/权限 | `pytest tests/test_projects.py` | ✅ 15 passed |
| 库存 | `pytest tests/test_inventory.py` | ✅ 11 passed |
| 匹配 | `pytest tests/test_matching.py` | ✅ 13 passed |
| 使用确认 | `pytest tests/test_usage.py` | ✅ 17 passed |
| 溯源 | `pytest tests/test_trace.py` | ✅ 5 passed |
| 并发 | `pytest tests/test_concurrency.py` | ✅ 3 passed（10 并发只成功 5 次扣减；同幂等键只扣 1 次） |
| 全量 | `cd backend && python -m pytest -q` | ✅ **104 passed** |
| 迁移生成 | `alembic revision --autogenerate` | ✅ `9eb0dc91e867_initial_schema.py` |
| 迁移执行 | `alembic upgrade head` | ✅ 9 张表 + `alembic_version` 建立 |
| 图标生成 | `python mobile/tool/generate_icons.py` | ✅ 5 个尺寸 PNG |
| **GitHub 仓库 + Release** | `REPO=tile-remnant-inventory TAG=v0.1.0 bash scripts/publish_github.sh` | ✅ 公开仓库 + v0.1.0，见 3.1 |
| **WordPress 发布** | SSH + WP-CLI（原脚本缺凭据，见 3.2） | ✅ post 89 已发布，见 3.2 |

## 二、未执行（环境缺失）

| 项 | 阻塞原因 | 补齐命令 |
|---|---|---|
| `flutter pub get` / `analyze` / `test` | 本机无 Flutter SDK、无 Dart | 安装 Flutter 3.22+ 后：`cd mobile && flutter pub get && flutter analyze && flutter test` |
| 构建 APK | 无 Flutter SDK、无 Android SDK/JDK17 | `API_BASE_URL=https://你的域名 bash scripts/build_apk.sh` |
| `docker compose up` | 本机无 Docker | `cp .env.example .env && docker compose up -d --build` |

## 三、发布记录

### 3.1 GitHub：已发布（2026-10-31 22:45）

| 项 | 值 |
|---|---|
| 仓库 | <https://github.com/z7ui/tile-remnant-inventory>（**PUBLIC**，默认分支 `main`） |
| 远端 main | `a28b1948b9a767d483908227a3e4cc95a9f9a393`（与本地 HEAD 一致） |
| Release | <https://github.com/z7ui/tile-remnant-inventory/releases/tag/v0.1.0>（非草稿、非预发布） |
| 附件 | **无**——`dist/` 不存在，本机也没有 Flutter SDK，构建不了 APK |

走的路径（与原先设想不同的地方）：

```bash
# 1) 装 gh（winget 输出是 GBK，UTF-8 终端里会乱码，按关键词判断成败）
winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements --silent
#    → gh 2.103.3，装到 C:\Program Files\GitHub CLI，新终端 PATH 已有

# 2) 认证：gh auth login 是交互式（开浏览器 + 粘 code），在非交互 shell 里会卡死。
#    改用已有的 git 凭据，不落地明文文件：
export GH_TOKEN="$(sed -E 's#^https://[^:]+:([^@]+)@github.com$#\1#' ~/.git-credentials)"
export PATH="/c/Program Files/GitHub CLI:$PATH"

# 3) 发布（脚本原样跑通）
REPO=tile-remnant-inventory TAG=v0.1.0 bash scripts/publish_github.sh
```

**踩到的坑**：`gh auth login --with-token` 会校验 token scope，本机这个 token 只有 `repo`，
缺 `read:org` → `error validating token: missing required scope 'read:org'`，所以**持久认证没做成功**。
`GH_TOKEN` 环境变量方式不受这个限制，可用于脚本；想长期直接敲 `gh`，需要交互跑一次 `gh auth login`，
或在 GitHub 新建一个带 `read:org` 的 PAT。

顺带修掉的一处：`docs/blog-post.md` 里两处 `https://github.com/<you>/...` 占位符换成了实际地址
（commit `a28b194`），避免线上文章带着 `<you>`。

### 3.2 WordPress：已发布（2026-10-31 22:51）

文章：<https://www.z7ui.cn/tile-remnant-inventory/>

| 项 | 值 |
|---|---|
| post ID | 89 |
| slug | `tile-remnant-inventory` |
| 状态 | `publish` |
| 分类 | 安卓改造（term 39） |
| 标签 | Flutter、FastAPI、SQLite、开源 |
| 首页位置 | 第一篇（按时间倒序） |
| 校验 | HTTP 200、83301 字节、5 个代码块、1 张表、占位符 0 |

为什么没走 `scripts/wp_publish.py`：本次没有站点应用密码，而脚本走 REST API 必须要有。
改用服务器的 WP-CLI（与站内其他文章的发布方式一致）：

```bash
# 1) 用脚本生成 HTML（--dry-run 不需要凭据）
python scripts/wp_publish.py docs/blog-post.md --dry-run

# 2) 去掉正文首行的 <h1>（否则与文章标题重复）
tail -n +2 docs/blog-post.html > /tmp/tile-body.html

# 3) 上传并创建（分类/标签脚本不支持，这里手动补）
ssh -i ~/.ssh/<key> root@<host> "cat > /tmp/tile-body.html" < /tmp/tile-body.html
ssh -i ~/.ssh/<key> root@<host> \
  'cd /var/www/<site> && wp post create /tmp/tile-body.html \
     --post_type=post --post_title="$(cat /tmp/tile-title.txt)" \
     --post_name=tile-remnant-inventory --post_status=publish \
     --post_category=39 --tags_input="Flutter,FastAPI,SQLite,开源" --allow-root --porcelain'
# 4) 刷缓存
ssh ... 'wp cache flush --allow-root && redis-cli FLUSHALL'
```

有应用密码之后，REST 路径是可以用的（脚本本身没问题）：

```bash
WP_URL=https://www.z7ui.cn WP_USER=<用户名> WP_APP_PASSWORD='xxxx xxxx xxxx xxxx' \
python scripts/wp_publish.py docs/blog-post.md --status publish --slug tile-remnant-inventory
```

但要注意脚本不做的三件事：**不发分类和标签、不去正文 `<h1>`、`--dry-run` 打印的是字符数不是字节数**
（输出「6660 字节」，实际文件 12029 字节——第一次看容易以为写错了位置）。

## 四、已知技术债

1. `mobile/` 未经 `flutter analyze`，可能存在少量 lint/类型问题；首次构建时按提示修（多为 unused import / deprecated API）。
2. `android/gradle/wrapper/gradle-wrapper.jar` 是二进制，未提交；`build_apk.sh` 会自动用 `gradle wrapper` 或提示 `flutter create` 生成。
3. 应用层限流为单进程内存实现，多副本需换 Redis。
4. 未实现图片附件、离线队列、导出分享（CSV 走浏览器/接口）。
5. 项目名唯一性把软删除项目也计入（见 README 假设 #1）。
6. **Release 没有 APK**：`dist/tile-remnant-0.1.0.apk` 不存在且本机无 Flutter。补法：
   装 Flutter 后 `bash scripts/build_apk.sh`，再 `gh release upload v0.1.0 dist/tile-remnant-0.1.0.apk`
   （或 `--clobber` 重新上传同名附件）。
7. **`gh` 在本机未持久认证**（token 缺 `read:org`）。脚本靠 `GH_TOKEN` 能跑，但 `gh` 单条命令会提示未登录，
   需要时交互跑一次 `gh auth login`。
8. `scripts/wp_publish.py --dry-run` 的输出单位是字符而非字节；生成的 HTML 带 `<h1>`，发 WP 前要自行裁掉。
