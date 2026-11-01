# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/); versioning follows [SemVer](https://semver.org/lang/zh-CN/).

## [0.1.23] - 2026-11-01

### Added

#### 移动端（Flutter）
- 溯源页右上角新增「返回项目」按钮：溯源是「点子批次 → 再开一个溯源页」的一层层嵌套，
  点太深时按返回要按很多次；这个按钮一次退回**项目主页**（库存/匹配/流水/项目那个 shell），
  不是退回首页。实现上是给项目 shell 的路由命名 `/project`，按钮 `popUntil` 到它为止，
  并兜底「已经是根路由」的情况，避免找不到名字时抛异常。

## [0.1.0] - 2026-10-31

### Added

#### 后端
- FastAPI 应用骨架：统一错误体、请求 ID、安全响应头、双层限流。
- 9 张表：`devices`、`projects`、`project_members`、`project_invites`、`project_access_tokens`、`inventory_batches`、`usage_records`、`inventory_movements`、`audit_logs`。
- Alembic 初始迁移 `9eb0dc91e867`（已实际执行验证）。
- 设备注册 / 心跳；bcrypt 设备密钥（仅返回一次）。
- 项目：名称 NFKC + casefold 全局唯一、邀请码（10 位、长期有效、可撤销/重置）、成员管理、软删除。
- 项目访问令牌：sha256 存储、按设备签发、移除成员/删项目即撤销。
- 库存：仅矩形录入、`cm/mm/裸数字` 解析、筛选分页、片数调整、作废。
- 几何引擎：矩形并集建模、角切、面积守恒、L 形缺口描述、复合形兜底。
- 匹配：旋转、覆盖校验、浪费面积 + 余料价值 + 可切片数排序、多批次分配建议。
- 确认使用：事务扣减（行锁 + 乐观锁）、每片一条流水、余料入库/丢弃、幂等键、并发重试。
- 流水：筛选、CSV 导出（UTF-8 BOM）。
- 溯源：三列对比、父子链、关联流水。
- 104 个 pytest 用例。

#### 移动端（Flutter）
- Material 3 主题与设计 token（`app_theme.dart`），深色模式跟随系统。
- 项目列表 / 新建（实时查重）/ 扫码 / 输入邀请码 / 二维码展示。
- 项目内四个 Tab：库存、匹配、流水、项目。
- 库存录入（矩形、数字键盘、单位分段、位置快选、片数步进）。
- 匹配结果卡片：浪费面积、利用率、旋转、两种切法、余料预览、溯源入口。
- 确认使用：切法图示卡 + 余料处置图示卡 + 三列面积对比 + 防重复提交。
- 流水时间线 + 详情（切割示意、变动明细）。
- 溯源页：三列对比、链路节点、关联流水。
- 项目设置：邀请码、成员设备、移除关联、软删除。
- Canvas 图形组件 `TileShapePreview`：缺口斜线、刀路虚线、真实比例。

#### 部署与文档
- `docker-compose.yml`（api + nginx + 可选 postgres，均不暴露数据库端口）。
- Nginx HTTPS 配置：301 跳转、TLS1.2/1.3、HSTS、限流、请求体上限。
- `.env.example` 全量可配置项。
- 脚本：`build_apk.sh`、`publish_github.sh`、`backup.sh`、`restore.sh`、`dev_backend.sh`、`wp_publish.py`。
- 文档：API、数据库、溯源、安全、部署、备份恢复、交付状态、博客文章。
- GPL-3.0 许可证、CHANGELOG、Release Notes。

### Known limitations
- Flutter 端未在本环境执行 `analyze/test/build`（无 SDK）。
- 限流为单进程内存实现；多副本需 Redis。
- 未实现图片附件、离线写队列、iOS 适配。

[0.1.0]: https://github.com/<you>/tile-remnant-inventory/releases/tag/v0.1.0
