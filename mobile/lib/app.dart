import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/config.dart';
import 'core/session.dart';
import 'core/session_scope.dart';
import 'features/projects/project_list_page.dart';
import 'features/settings/server_setup_page.dart';
import 'widgets/common.dart';

class TileRemnantApp extends StatefulWidget {
  const TileRemnantApp({super.key});

  @override
  State<TileRemnantApp> createState() => _TileRemnantAppState();
}

class _TileRemnantAppState extends State<TileRemnantApp> {
  Session? _session;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _fatalError = null;
      _session = null;
    });
    try {
      final Session session = await Session.create();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _fatalError = errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '余砖管家',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final Session? session = _session;
    if (session == null) {
      return _BootScreen(error: _fatalError, onRetry: _boot);
    }
    return SessionScope(
      session: session,
      child: const ProjectListPage(),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool failed = error != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.accent(context),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('余砖管家', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '装修瓷砖余料库存与匹配',
                style: TextStyle(fontSize: 14, color: AppColors.sub(context)),
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (!failed)
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6))
              else ...<Widget>[
                ErrorBanner(message: error!, onRetry: onRetry),
                const SizedBox(height: AppSpacing.md),
                // release 包地址写死：不给改，只能重试
                if (!AppConfig.serverLocked)
                  TextButton.icon(
                    onPressed: () async {
                      final String? url = await Navigator.of(context).push<String>(
                        MaterialPageRoute<String>(builder: (_) => const ServerSetupPage()),
                      );
                      if (url != null) {
                        await Session.persistServerUrl(url);
                      }
                      onRetry();
                    },
                    icon: const Icon(Icons.dns_outlined),
                    label: const Text('修改服务器地址'),
                  ),
                if (AppConfig.serverLocked)
                  Text(
                    '服务器地址已固定在安装包内（${AppConfig.defaultBaseUrl}），'
                    '连不上请检查网络或稍后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '服务器地址：${AppConfig.defaultBaseUrl}',
                  style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
