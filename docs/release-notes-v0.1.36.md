# v0.1.36 · 服务端公告（后门通道）

App 启动时会拉一条服务端公告，你可以随时下发标题、正文和最多 4 个按钮。

## 怎么发公告

编辑服务器上的 `/opt/tile/announcements.json`（改完立即生效，**不用重启**）：

```json
{
  "announcements": [
    {
      "id": "2026-11-08-upgrade",
      "enabled": true,
      "title": "需要更新",
      "body": "0.1.30 以下版本即将停止服务，请更新后再用。",
      "dismissible": true,
      "min_version": "0.0.0",
      "max_version": "0.1.29",
      "buttons": [
        {"label": "去下载", "action": "open_url", "target": "https://www.z7ui.cn/apps/"},
        {"label": "稍后", "action": "dismiss"},
        {"label": "", "action": "none"},
        {"label": "", "action": "none"}
      ]
    }
  ]
}
```

## 按钮动作（白名单）

| action | 效果 |
|---|---|
| `open_url` | 用浏览器打开 `target` |
| `dismiss` | 关闭公告 |
| `reload` | 重载配置 / 刷新项目列表 |
| `open_about` | 打开「关于」页 |
| `copy` | 复制 `target` 文本 |
| `none` | 空槽位，不显示 |

`label` 留空或 `action` 为 `none` 的按钮不会渲染。`dismissible: false` 时不能点外部关闭。

## 筛选条件

- `min_version` / `max_version`：只对指定版本区间显示；
- `starts_at` / `ends_at`：只在一段时间内显示（ISO 时间，如 `2026-11-08T00:00:00`）。

完整变更见仓库 `CHANGELOG.md`。
