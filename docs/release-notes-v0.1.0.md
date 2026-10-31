# v0.1.0 · 首个可运行版本

装修瓷砖余料库存与匹配管理 App —— 后端 + Flutter 移动端 + 部署编排。

## 这个版本能做什么

- 无账号设备身份：注册即用，扫码加入项目，长期保留
- 项目名全局唯一（忽略大小写与首尾空格）
- 矩形余砖录入：`800` / `80cm` / `800mm` 自动解析，统一存整数毫米
- 尺寸匹配：允许旋转 90°，需求必须完全覆盖，按「浪费面积 → 余料价值」排序
- 两种切法（长边/短边切到底）+ 两种余料处置（入库/丢弃），带实时图示
- 切割余料自动入库，支持 L 形异形；丢弃也写流水
- 完整溯源：原砖 / 需求 / 余料三列对比 + 父子链 + 关联流水
- 流水只追加，支持筛选与 CSV 导出
- 并发安全：行锁 + 乐观锁 + 幂等键，不超扣、不重复扣
- Docker Compose + Nginx HTTPS 部署

## 安装 APK

本 Release 不附带预编译 APK（构建环境无 Android SDK）。请自行构建：

```bash
# 前置：Flutter 3.22+、Android SDK platform 35、JDK 17
API_BASE_URL=https://你的域名 bash scripts/build_apk.sh
# 产物：dist/tile-remnant-0.1.0.apk
```

首次启动在 App 内填写同一个 HTTPS 地址，或构建时通过 `--dart-define=API_BASE_URL=...` 预置。

## 服务端

```bash
cp .env.example .env    # 改 PUBLIC_BASE_URL / DATABASE_URL
mkdir -p deploy/certs   # 放 fullchain.pem / privkey.pem
docker compose up -d --build
```

详见 `docs/deployment.md`。

## 验证情况

- 后端 `pytest`：104 passed
- Alembic 初始迁移：已实际执行
- Flutter `analyze` / `test` / APK 构建：未在本环境执行（无 SDK）
- GitHub / WordPress 发布：见 `docs/DELIVERY-STATUS.md`

## 许可

GPL-3.0
