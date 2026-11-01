# 签名材料备份

release keystore 等于这个 App 的「所有权凭证」：拿到它就能签出可覆盖升级的包。
丢了会怎样——已安装的用户再也装不上新版本，只能卸载重装，数据全丢。

所以它不进 git（`.gitignore` 已排除 `*.jks` / `*.keystore` / `key.properties`），
但也**不能只存在一台机器上**。

## 两处存放

| 位置 | 内容 | 说明 |
| --- | --- | --- |
| 本机 `D:/flutte/keystore/` | `tile-upload.jks` + `PASSWORD.txt` | 构建时用，明文 |
| 服务器 `/opt/apps-archive/signing/` | AES-256 加密包 + 明文清单 | 第二份，供恢复 |

在线地址（可直接浏览）：

```
https://www.z7ui.cn/apps-archive/
https://www.z7ui.cn/apps-archive/signing/README.md      ← 明文清单，含指纹与恢复步骤
https://www.z7ui.cn/apps-archive/signing/signing-backup-20261101.tar.gz.enc
```

同一份归档里还有 qingdou / edgepad / routinex / ruletree 的签名密钥，
统一用同一个口令加密。**口令不写在任何 README 里，也不落服务器。**

## 解密

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in signing-backup-20261101.tar.gz.enc \
  -out signing-backup-20261101.tar.gz
tar xzf signing-backup-20261101.tar.gz
```

Windows 没有 openssl 时用 Git Bash（自带）或 WSL。

## 本项目的密钥信息

| 项 | 值 |
| --- | --- |
| keystore | `tile-upload.jks` |
| 别名 | `tile-upload` |
| 包名 | `com.tileremnant.app` |
| 证书 SHA-256 | `40:7C:AE:1F:EB:81:49:0C:56:77:DD:52:09:0B:69:1C:9A:24:CD:E8:97:42:56:50:DE:37:EB:93:30:8D:AF:B0` |

核对：

```bash
keytool -list -v -keystore tile-upload.jks -storepass <口令> | grep SHA256
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

两处指纹必须一致——不一致说明用的不是同一把密钥，覆盖安装会被系统拒绝。

## 换机器时

1. 从服务器解出 `tile-upload.jks` 和口令
2. 放到任意安全路径
3. 写 `mobile/android/key.properties`：

```properties
storePassword=<口令>
keyPassword=<口令>
keyAlias=tile-upload
storeFile=<jks 的绝对路径>
```

4. `flutter build apk --release`（该文件存在时自动启用 release 签名，否则退回 debug）

## 建议

再离线存一份（U 盘 / 密码管理器）。服务器只是"第二份"，不是"唯一一份"——
服务器到期、误删、机房故障都是真实风险。
