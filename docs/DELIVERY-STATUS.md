# 交付状态与阻塞项

> 本文件只写**实际执行过的结果**。没有执行的事情一律标为「未执行」，并给出精确命令。

生成时间：2026-10-31（Asia/Shanghai）

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

## 二、未执行（环境缺失）

| 项 | 阻塞原因 | 补齐命令 |
|---|---|---|
| `flutter pub get` / `analyze` / `test` | 本机无 Flutter SDK、无 Dart | 安装 Flutter 3.22+ 后：`cd mobile && flutter pub get && flutter analyze && flutter test` |
| 构建 APK | 无 Flutter SDK、无 Android SDK/JDK17 | `API_BASE_URL=https://你的域名 bash scripts/build_apk.sh` |
| `docker compose up` | 本机无 Docker | `cp .env.example .env && docker compose up -d --build` |
| GitHub 仓库 + Release | 无 `gh` CLI；已连接的 GitHub 集成无建仓权限（403） | `bash scripts/publish_github.sh`（详见 3.1） |
| WordPress 发布 | 无站点地址 / 用户名 / 应用密码（本会话无 WP 连接器） | `WP_URL=… WP_USER=… WP_APP_PASSWORD=… python scripts/wp_publish.py docs/blog-post.md --status publish` |

## 三、发布阻塞项的精确说明

### 3.1 GitHub

**已尝试**，两条路径都走不通：

1. `gh` CLI：本机未安装 → `bash scripts/publish_github.sh` 输出 `BLOCKED: 未安装 GitHub CLI (gh)`，退出码 2。
2. 已连接的 GitHub 集成（账号 `z7ui`，`get_me` 成功）：
   - `create_repository`（`POST /user/repos`）→ `403 Resource not accessible by integration`
   - 该集成的安装令牌没有仓库创建权限，只能读已授权仓库。

所以**仓库与 Release 均未创建**，也没有伪造链接。本地 `git` 仓库已就绪：

```
$ git log --oneline
0308071 chore: 标记部署脚本可执行
*** chore: 统一换行符，避免容器内 shell 脚本因 CRLF 失败
4d55471 feat: 瓷砖余料库存与匹配管理 v0.1.0
```

补齐方式（任选其一）：

```bash
# A. 安装 gh 并认证（最省事）
winget install --id GitHub.cli
gh auth login
REPO=tile-remnant-inventory TAG=v0.1.0 bash scripts/publish_github.sh

# B. 网页建空仓（不要勾选 README/gitignore），再推
git remote add origin git@github.com:<you>/tile-remnant-inventory.git
git push -u origin main
# 然后在网页创建 v0.1.0 Release，正文用 docs/release-notes-v0.1.0.md

# C. 给 GitHub 集成补权限
在 GitHub App 设置里授予 Administration: Read & write 并重新安装到该账号，再调用 create_repository
```

Release 附件：本环境无法构建 APK，请先跑 `bash scripts/build_apk.sh` 得到 `dist/tile-remnant-0.1.0.apk`，再执行 `gh release create v0.1.0 dist/tile-remnant-0.1.0.apk --notes-file docs/release-notes-v0.1.0.md`。

### 3.2 WordPress

当前会话没有可用的 WordPress 凭据（站点地址 / 用户名 / 应用密码），因此**没有发布**，也没有伪造发布结果。

文章已就绪：`docs/blog-post.md`（含标题、导语、小标题、代码块、表格，可直接粘贴到古腾堡编辑器）。

两条路径：

```bash
# A. 直接复制 Markdown 到 WP 编辑器（古腾堡支持 Markdown 粘贴）
cat docs/blog-post.md

# B. REST API 发布（推荐，自动转 HTML）
WP_URL=https://你的博客域名 \
WP_USER=你的用户名 \
WP_APP_PASSWORD='xxxx xxxx xxxx xxxx' \
python scripts/wp_publish.py docs/blog-post.md --status publish
```

应用密码生成：WP 后台 → 用户 → 个人资料 → 页面底部「应用程序密码」。

## 四、已知技术债

1. `mobile/` 未经 `flutter analyze`，可能存在少量 lint/类型问题；首次构建时按提示修（多为 unused import / deprecated API）。
2. `android/gradle/wrapper/gradle-wrapper.jar` 是二进制，未提交；`build_apk.sh` 会自动用 `gradle wrapper` 或提示 `flutter create` 生成。
3. 应用层限流为单进程内存实现，多副本需换 Redis。
4. 未实现图片附件、离线队列、导出分享（CSV 走浏览器/接口）。
5. 项目名唯一性把软删除项目也计入（见 README 假设 #1）。
