# 余砖管家 · Flutter 客户端

Android APK，无账号、扫码加入、离线只读。

## 环境

- Flutter 3.22+（Dart 3.4+）
- Android SDK platform 35 / build-tools 35
- JDK 17

## 运行

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://你的域名
```

后端地址也可以在 App 首次启动/设置里填写（只接受 HTTPS，本机调试可用 `http://10.0.2.2:8000`）。

## 构建 APK

```bash
# 在仓库根目录
API_BASE_URL=https://你的域名 bash scripts/build_apk.sh
```

或手工：

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://你的域名
# build/app/outputs/flutter-apk/app-release.apk
```

签名见根 README「构建 APK」。

## 测试与检查

```bash
flutter analyze
flutter test
```

`test/formatters_test.dart` 覆盖尺寸解析/格式化/幂等键；
`test/flow_test.dart` 覆盖邀请码解析、L 形图示渲染、批次模型解析。

## 结构

```
lib/
├── core/          # 主题 token、API 客户端、会话与安全存储、模型、单位格式化
├── widgets/       # TileShapePreview（Canvas 俯视图）、库存卡、尺寸输入、通用组件
└── features/
    ├── projects/  # 列表、新建、加入、扫码、二维码
    ├── home/      # 底部导航壳
    ├── inventory/ # 库存列表 + 录入
    ├── match/     # 匹配 + 确认使用
    ├── movements/ # 流水 + 详情
    ├── trace/     # 溯源对比
    └── settings/  # 项目设置、服务器地址
```

## 图标

```bash
python tool/generate_icons.py   # 无第三方依赖，生成 5 个尺寸
```

## 已知限制

- 未经 `flutter analyze`（开发环境无 SDK），首次构建可能有个别 lint 提示。
- `android/gradle/wrapper/gradle-wrapper.jar` 为二进制未提交，构建脚本会自动补齐。
