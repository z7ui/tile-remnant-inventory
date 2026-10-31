# 安全说明

## 威胁模型

| 威胁 | 对策 |
|---|---|
| 抓包读取数据 | 全链路 HTTPS；App 拒绝非 HTTPS；Android 禁用明文 |
| 猜项目 ID 拉数据 | 项目级接口必须同时提供设备 ID + 项目令牌，并校验成员关系，否则 403 |
| 拿到一台手机就拿到全部项目 | 设备令牌按项目签发，只能访问已加入的项目 |
| 数据库被公网访问 | 数据库只在容器网络内，Compose 不映射端口；Nginx 不代理 5432/3306 |
| 密钥泄漏 | 设备密钥 bcrypt 哈希、项目令牌 sha256 哈希；`.env` 不入库；日志不打印凭证 |
| 重放确认请求重复扣减 | 幂等键 + 数据库唯一约束 |
| 并发超扣 | 行锁 + 乐观锁版本号 + 原子条件更新，冲突重试后失败返回 409 |
| 暴力破解邀请码 | 31^10 ≈ 8×10^14 组合；注册/加入接口限流；无效码统一 404 |
| 恶意大请求 | 请求体上限 1MB；分页上限 200；字段长度全部受限 |
| 跨站脚本（若用浏览器调试） | 全部 JSON；`X-Content-Type-Options: nosniff`；`X-Frame-Options: DENY` |

## 传输

- Nginx：80 → 301 HTTPS；TLS1.2/1.3；HSTS 一年；`server_tokens off`。
- 可选 AES-GCM 字段加密：本期未启用（数据本身不含个人身份信息）。如需启用，建议在 `inventory_batches.note`、`location` 上做应用层加密，密钥放 `.env` 的 `FIELD_ENCRYPTION_KEY`，并注意加密后无法做模糊搜索。

## 认证与授权

```
注册:  POST /api/devices/register          → device_id + device_secret（仅一次）
建项目: X-Device-Id + X-Device-Secret       → project_token（长期）
日常:  X-Device-Id + X-Project-Token        → 每次校验成员关系
```

- 设备密钥 bcrypt cost 12（`.env` 可调），比较用 `bcrypt.checkpw`；
- 项目令牌 32 字节随机，仅存 sha256，前缀 6 位用于排障；
- 移除成员 / 删除项目会同时撤销令牌；
- 拥有者专属操作（查看/撤销邀请码、成员管理、删除项目）在服务端二次校验，不依赖前端隐藏按钮。

## 日志

- 不记录请求体、`X-Device-Secret`、`X-Project-Token`；
- 访问日志只保留方法、路径、状态码、耗时、请求 ID；
- 审计表记录动作与目标 ID，`detail` 中不含凭证。

## 速率限制

| 层 | 规则 |
|---|---|
| 应用 | 读 240/min/IP，写 60/min/IP（滑动窗口，超限 429 + Retry-After） |
| Nginx | `/api/` 8r/s burst 20；写接口 2r/s burst 10 |

多副本部署时把 `app/ratelimit.py` 换成 Redis 实现（接口已隔离，改一个类即可）。

## 部署检查清单

- [ ] `.env` 权限 600，未提交到 git（`.gitignore` 已覆盖）
- [ ] `PUBLIC_BASE_URL` 为 https 且与证书域名一致
- [ ] 证书有效期监控（acme.sh / certbot 自动续期）
- [ ] 数据库目录只挂载数据卷，不对宿主暴露端口
- [ ] 备份文件异地存放，且恢复演练过至少一次
- [ ] `docker compose ps` 中 api 只有 `expose`，没有 `ports`
- [ ] 用手机浏览器访问 `http://域名` 应 301 到 https

## 已知限制

1. 无账号体系意味着设备丢失 = 该设备令牌仍有效，需拥有者手动移除该设备。
2. 邀请码一旦泄漏，任何拿到码的人都能加入；请定期重置。
3. 单进程内存限流不适合多副本，需 Redis。
4. 未做端到端加密（E2EE），服务端可见明文业务数据；这是「数据存自己博客主机」的必然结果。
