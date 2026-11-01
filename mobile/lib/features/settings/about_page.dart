import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';

/// 关于：版本、服务器地址、设备身份、后端连通性。
///
/// 服务器地址在这里**只读展示**——release 包里它是编译期写死的，
/// 界面上不提供修改入口（原因见 [AppConfig.defaultBaseUrl] 的注释）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _started = false;
  bool _checking = false;
  String? _serverVersion;
  String? _serverEnv;
  String? _serverError;
  int? _latencyMs;

  bool _checkingUpdate = false;
  Map<String, dynamic>? _latest;
  String? _updateError;

  /// 服务端清单里的 versionCode 比自己大，才算有新版本。
  bool get _hasUpdate {
    final Map<String, dynamic>? info = _latest;
    if (info == null) return false;
    final int remote = (info['versionCode'] as num?)?.toInt() ?? 0;
    return remote > AppConfig.buildNumber;
  }

  String _fmtSize(Object? bytes) {
    final int? value = (bytes as num?)?.toInt();
    if (value == null || value <= 0) return '';
    final double mb = value / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateError = null;
    });
    try {
      final Session session = SessionScope.of(context);
      // 版本清单是服务器上的静态文件（/tile-api/apk/version.json），不经过后端。
      final dynamic json = await session.api.get('/apk/version.json');
      if (!mounted) return;
      setState(() {
        _latest = Map<String, dynamic>.from(json as Map);
        _checkingUpdate = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateError = errorMessage(error);
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _downloadUpdate() async {
    final Object? raw = _latest?['apk_url'];
    if (raw is! String || raw.isEmpty) {
      showSnack(context, '清单里没有下载地址', error: true);
      return;
    }
    final Uri uri = Uri.parse(raw);
    // 交给系统浏览器：它会先下载到「下载」目录，点通知即可安装。
    // 不在应用内自建下载器——省掉存储权限、断点续传、Android 7+ 的 FileProvider
    // 和 targetSdk 35 的「安装未知应用」授权弹窗。
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showSnack(context, '没有可用的浏览器打开下载链接', error: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _ping();
  }

  Future<void> _ping() async {
    setState(() {
      _checking = true;
      _serverError = null;
    });
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Session session = SessionScope.of(context);
      final dynamic json = await session.api.get('/healthz');
      watch.stop();
      if (!mounted) return;
      final Map<dynamic, dynamic> map = json as Map<dynamic, dynamic>;
      setState(() {
        _serverVersion = map['version']?.toString();
        _serverEnv = map['environment']?.toString();
        _latencyMs = watch.elapsedMilliseconds;
        _checking = false;
      });
    } catch (error) {
      watch.stop();
      if (!mounted) return;
      setState(() {
        _serverError = errorMessage(error);
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Session session = SessionScope.of(context);
    final String deviceId = session.deviceId ?? '未注册';
    final String shortId =
        deviceId.length > 10 ? deviceId.substring(0, 10) : deviceId;

    return Scaffold(
      appBar: buildAppBar(context, '关于'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Column(
                children: <Widget>[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.grid_view_rounded,
                        size: 38, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('余砖管家',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    '装修瓷砖余料库存与匹配',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.sub(context)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'v${AppConfig.appVersion}',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.sub(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            const SectionTitle(title: '数据服务器', subtitle: '库存和流水都存在这里'),
            _InfoCard(
              rows: <Widget>[
                _Row(
                    label: '服务地址',
                    value: AppConfig.defaultBaseUrl,
                    mono: true,
                    selectable: true),
                _Row(
                  label: '状态',
                  value: _checking
                      ? '检查中…'
                      : (_serverError != null
                          ? '连不上：$_serverError'
                          : '正常${_latencyMs != null ? ' · ${_latencyMs}ms' : ''}'),
                  valueColor: _checking
                      ? AppColors.sub(context)
                      : (_serverError != null
                          ? AppColors.danger
                          : AppColors.success),
                ),
                if (_serverVersion != null)
                  _Row(
                    label: '服务版本',
                    value:
                        'v$_serverVersion${_serverEnv != null ? ' · $_serverEnv' : ''}',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _checking ? null : _ping,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新检测'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            const SectionTitle(title: '版本更新', subtitle: '新版本从工地服务器直接下载'),
            _InfoCard(
              rows: <Widget>[
                _Row(
                    label: '当前版本',
                    value:
                        'v${AppConfig.appVersion}（构建 ${AppConfig.buildNumber}）'),
                if (_latest != null)
                  _Row(
                    label: '线上版本',
                    value: _hasUpdate
                        ? '发现新版本 v${_latest!['version'] ?? '?'}'
                            '${_fmtSize(_latest!['size']).isEmpty ? '' : ' · ${_fmtSize(_latest!['size'])}'}'
                        : '已是最新版本',
                    valueColor:
                        _hasUpdate ? AppColors.primary : AppColors.success,
                  ),
                if (_updateError != null)
                  _Row(
                      label: '检查失败',
                      value: _updateError!,
                      valueColor: AppColors.danger),
                if (_hasUpdate &&
                    (_latest!['notes']?.toString().trim().isNotEmpty ?? false))
                  _Row(label: '更新内容', value: _latest!['notes'].toString()),
              ],
            ),
            // 下载按钮必须是整行大按钮：之前它挤在「检查更新」旁边，
            // 窄屏上直接被挤没了，用户看得到「发现新版本」却找不到下载入口。
            if (_hasUpdate) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloadUpdate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.download, size: 20),
                  label: Text(
                    '下载并安装 v${_latest!['version'] ?? ''}'
                    '${_fmtSize(_latest!['size']).isEmpty ? '' : ' · ${_fmtSize(_latest!['size'])}'}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _checkingUpdate ? null : _checkUpdate,
                icon: _checkingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_alt, size: 18),
                label: Text(_checkingUpdate ? '检查中…' : '检查更新'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            const SectionTitle(title: '本机身份', subtitle: '不需要注册账号'),
            _InfoCard(
              rows: <Widget>[
                _Row(
                    label: '本机编号',
                    value: shortId,
                    mono: true,
                    selectable: true),
                const _Row(label: '说明', value: '长按可复制。遇到问题时把这串编号发给管理员，方便定位。'),
              ],
            ),

            const SizedBox(height: AppSpacing.md),
            const SectionTitle(title: '其它'),
            _InfoCard(
              rows: <Widget>[
                _Row(label: '开源协议', value: 'GPL-3.0'),
                _LinkRow(
                  label: '源码',
                  text: 'github.com/z7ui/tile-remnant-inventory',
                  url: 'https://github.com/z7ui/tile-remnant-inventory',
                ),
                _LinkRow(
                  label: '博客',
                  text: 'www.z7ui.cn',
                  url: 'https://www.z7ui.cn/',
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            Text(
              '库存、流水和溯源记录都保存在工地的服务器上，不会上传到任何第三方。',
              style: TextStyle(
                  fontSize: 12, height: 1.5, color: AppColors.sub(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: Column(children: rows),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.mono = false,
    this.selectable = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final bool selectable;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: 13,
      height: 1.35,
      fontFamily: mono ? 'monospace' : null,
      color: valueColor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label,
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.sub(context))),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value, style: style)
                : Text(value, style: style),
          ),
        ],
      ),
    );
  }
}

/// 可点击的外链行：整行可点，右侧有「在浏览器中打开」的图标。
/// 之前只是可复制的文本，用户还得手动复制到浏览器地址栏。
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.text, required this.url});

  final String label;
  final String text;
  final String url;

  Future<void> _open(BuildContext context) async {
    final bool ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showSnack(context, '没有可用的浏览器打开这个链接', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 76,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.sub(context))),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child:
                  Icon(Icons.open_in_new, size: 15, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
