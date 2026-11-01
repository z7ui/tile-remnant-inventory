import 'package:flutter/material.dart';

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
    final String shortId = deviceId.length > 10 ? deviceId.substring(0, 10) : deviceId;

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
                      color: AppColors.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.grid_view_rounded, size: 38, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('余砖管家', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    '装修瓷砖余料库存与匹配',
                    style: TextStyle(fontSize: 13, color: AppColors.sub(context)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'v${AppConfig.appVersion}',
                    style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            const SectionTitle(title: '服务器', subtitle: '地址随安装包固定，界面上无法修改'),
            _InfoCard(
              rows: <Widget>[
                _Row(label: '地址', value: AppConfig.defaultBaseUrl, mono: true, selectable: true),
                _Row(
                  label: '状态',
                  value: _checking
                      ? '检查中…'
                      : (_serverError != null
                          ? '连不上：$_serverError'
                          : '正常${_latencyMs != null ? ' · ${_latencyMs}ms' : ''}'),
                  valueColor: _checking
                      ? AppColors.sub(context)
                      : (_serverError != null ? AppColors.danger : AppColors.success),
                ),
                if (_serverVersion != null)
                  _Row(
                    label: '后端版本',
                    value: 'v$_serverVersion${_serverEnv != null ? ' · $_serverEnv' : ''}',
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
            const SectionTitle(title: '本机设备', subtitle: '没有账号，设备身份就是凭证'),
            _InfoCard(
              rows: <Widget>[
                _Row(label: '设备 ID', value: shortId, mono: true, selectable: true),
                const _Row(label: '说明', value: '长按可复制。联系技术支持时提供它便于定位。'),
              ],
            ),

            const SizedBox(height: AppSpacing.md),
            const SectionTitle(title: '其它'),
            _InfoCard(
              rows: <Widget>[
                _Row(label: '协议', value: 'GPL-3.0'),
                _Row(label: '源码', value: 'github.com/z7ui/tile-remnant-inventory', mono: true, selectable: true),
                _Row(label: '技术栈', value: 'Flutter · FastAPI · SQLite'),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            Text(
              '余料入库、切割记账、溯源查询都在本地服务器上完成，本 App 不上传任何第三方数据。',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.sub(context)),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
            child: Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.sub(context))),
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
