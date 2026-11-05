import 'package:flutter/foundation.dart' show kReleaseMode;

/// Static configuration.
class AppConfig {
  const AppConfig._();

  static const String appVersion = '0.1.31';

  /// 构建号，必须和 `pubspec.yaml` 里 `version: x.y.z+N` 的 N 保持一致。
  /// 判断有没有新版本用的是它（字符串比较 "0.1.10" < "0.1.9" 会出错）。
  static const int buildNumber = 32;

  /// 服务器地址在**编译时**定死：
  ///   flutter build apk --dart-define=API_BASE_URL=https://www.z7ui.cn/tile-api
  ///
  /// 不允许运行时改的原因：这个 App 没有账号体系，设备身份（设备 ID + 密钥）
  /// 是发给「服务器」的。如果地址能在界面上随便填，等于给了一条把设备密钥
  /// 骗到第三方服务器的路。地址跟着安装包走，改地址只能换安装包。
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://www.z7ui.cn/tile-api',
  );

  /// Release 构建锁定服务器地址；debug 保留可改（要连本机/测试机）。
  static bool get serverLocked => kReleaseMode;

  static const String inviteScheme = 'tileremnant';

  /// Cleartext HTTP is only tolerated for local development hosts.
  static bool isLocalHost(Uri uri) {
    const allowed = <String>{'localhost', '127.0.0.1', '10.0.2.2', '::1'};
    return allowed.contains(uri.host);
  }
}
