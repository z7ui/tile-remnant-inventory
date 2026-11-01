# 软件合集页的维护

页面：<https://www.z7ui.cn/apps/>（WordPress post ID **91**）
源稿：`docs/software-collection.md` → `python scripts/wp_publish.py` 生成 HTML

## 某个 App 发了新版，三步

```bash
# 1. 同步安装包（只拉有变动的，自动删旧版）
bash scripts/sync_app_apks.sh

# 2. 改文档里的版本号和下载链接
#    docs/software-collection.md 里对应那一节的「版本 0.x.y」
#    和 downloads/xxx-0.x.y.apk

# 3. 重新生成并更新文章
python scripts/wp_publish.py docs/software-collection.md --dry-run
ssh ... 'cat > /tmp/sc.html' < docs/software-collection.html
cd /var/www/z7ui.cn && wp post update 91 /tmp/sc.html --allow-root
wp cache flush --allow-root && redis-cli FLUSHALL
```

只想看哪些 App 有新版本、先不下载：

```bash
bash scripts/sync_app_apks.sh --check
```

## 命名规则

统一 `<前缀>-<版本>.apk`，版本取自 GitHub tag 去掉 `V` 前缀：

| App | 前缀 | 示例 |
| --- | --- | --- |
| 余砖管家 | `tile-remnant` | `tile-remnant-0.1.14.apk` |
| 边触 | `edgepad` | `edgepad-0.2.apk` |
| 规则树 | `ruletree` | `ruletree-0.12.apk` |
| 定时快捷 | `routinex` | `routinex-1.4.apk` |
| 幕布 | `Curtain` | `Curtain-1.7.apk` |
| PIN 滑动输入 | `PinSwipe` | `PinSwipe-1.2.apk` |
| PIN 滑动输入 for Galaxy | `PinSwipeForGalaxy` | `PinSwipeForGalaxy-1.1.apk` |

**前缀一定带横杠**（`PinSwipe-` 而不是 `PinSwipe`），否则清理时会误删
`PinSwipeForGalaxy-*`——两个项目名字前缀相同。

## 清理规则

脚本上传完新版后，会删掉服务器上 `${前缀}-*.apk` 里除新文件以外的所有包。
**服务器上每个 App 只留一版**，不堆历史。

历史版本要看的话去 GitHub Release，那边是完整的。

## 不对外发布的 App

`qingdou`（清抖）在脚本里标了 `no`：不下载、还会主动删掉服务器上残留的包。
文章里也只留简介和原文链接，没有下载入口。

理由：针对抖音的模块，不对外分发。

## 目录与地址

```
服务器 /opt/apps-archive/downloads/
公网 https://www.z7ui.cn/apps-archive/downloads/<文件名>
```

nginx 里 `/apps-archive/` 映射到 `/opt/apps-archive/`，apk 的 MIME 是
`application/vnd.android.package-archive`（浏览器会直接下载而不是当文本打开）。
