import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../home/project_shell_page.dart';
import '../projects/create_project_page.dart';
import '../projects/join_project_page.dart';
import '../projects/qr_scan_page.dart';
import '../settings/about_page.dart';
import '../settings/server_setup_page.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  bool _refreshing = false;
  bool _launchCheckStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_launchCheckStarted) return;
    _launchCheckStarted = true;
    // 放到下一帧：此时 Navigator 已就绪，弹窗不会撞上首帧构建
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateOnLaunch());
  }

  /// 启动时静默检查一次更新；有新版才弹窗。
  /// 任何失败都不打扰用户——断网、服务器维护都算正常情况。
  Future<void> _checkUpdateOnLaunch() async {
    if (!mounted) return;
    final Session session = SessionScope.of(context);
    if (!session.prefs.autoCheckUpdate) return;
    try {
      final dynamic json = await session.api.get('/apk/version.json');
      if (!mounted) return;
      final Map<String, dynamic> info = Map<String, dynamic>.from(json as Map);
      final int remote = (info['versionCode'] as num?)?.toInt() ?? 0;
      if (remote <= AppConfig.buildNumber) return;
      // 用户点过「忽略此版本」：同一个构建号不再主动弹
      if (remote <= session.prefs.ignoredVersionCode) return;
      await _showUpdateDialog(session, info, remote);
    } catch (_) {
      // 静默
    }
  }

  Future<void> _showUpdateDialog(
      Session session, Map<String, dynamic> info, int remote) async {
    final String version = '${info['version'] ?? ''}';
    final String size = _formatSize(info['size']);
    final String notes = (info['notes'] ?? '').toString().trim();

    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('发现新版本 v$version'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (size.isNotEmpty)
              Text('安装包 $size',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.sub(dialogContext))),
            if (notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(notes, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('ignore'),
            child: const Text('忽略此版本'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('download'),
            child: const Text('去下载'),
          ),
        ],
      ),
    );

    if (action == 'ignore') {
      await session.prefs.setIgnoredVersionCode(remote);
      if (mounted) showSnack(context, 'v$version 不再提示，之后的新版本会再提醒');
      return;
    }
    if (action == 'download') {
      final Object? url = info['apk_url'];
      if (url is! String || url.isEmpty) return;
      final bool ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showSnack(context, '没有可用的浏览器打开下载链接', error: true);
      }
    }
  }

  String _formatSize(Object? bytes) {
    final int? value = (bytes as num?)?.toInt();
    if (value == null || value <= 0) return '';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final Session session = SessionScope.of(context);
    try {
      await session.refreshProjects();
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openProject(JoinedProject project) async {
    final Session session = SessionScope.of(context);
    session.select(project);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProjectShellPage(project: project)),
    );
    if (mounted) await _refresh();
  }

  Future<void> _createProject() async {
    final JoinedProject? created = await Navigator.of(context).push<JoinedProject>(
      MaterialPageRoute<JoinedProject>(builder: (_) => const CreateProjectPage()),
    );
    if (!mounted) return;
    await _refresh();
    if (created != null && mounted) {
      await _openProject(created);
    }
  }

  Future<void> _scan() async {
    final String? payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (!mounted) return;
    if (payload == null) return;
    final Session session = SessionScope.of(context);
    try {
      final JoinedProject project = await session.joinProjectFromPayload(payload);
      if (!mounted) return;
      await _refresh();
      await _openProject(project);
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _joinByCode() async {
    final JoinedProject? joined = await Navigator.of(context).push<JoinedProject>(
      MaterialPageRoute<JoinedProject>(builder: (_) => const JoinProjectPage()),
    );
    if (joined != null && mounted) {
      await _refresh();
      await _openProject(joined);
    }
  }

  Future<void> _openServerSetup() async {
    final Session session = SessionScope.of(context);
    final String? url = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => ServerSetupPage(initialUrl: session.serverUrl)),
    );
    if (!mounted || url == null || url == session.serverUrl) return;
    final bool ok = await confirmDanger(
      context,
      title: '更换服务器？',
      message: '本机已加入的项目会被清空，需要用新的邀请码重新加入。项目数据仍保留在原服务器。',
      confirmLabel: '更换',
    );
    if (!ok || !mounted) return;
    await session.setServer(url);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Session session = SessionScope.of(context);
    final List<JoinedProject> projects = session.projects;

    return Scaffold(
      appBar: buildAppBar(
        context,
        '余砖管家',
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
            tooltip: '关于',
            icon: const Icon(Icons.info_outline),
          ),
          // release 包里地址写死在安装包内，这个入口只在 debug 构建出现
          if (!AppConfig.serverLocked)
            IconButton(
              onPressed: _openServerSetup,
              tooltip: '服务器与同步设置',
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: <Widget>[
            if (session.offline)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: ErrorBanner(
                  message: '当前离线：显示的是本机缓存。提交操作会失败并提示重试。',
                  actionLabel: '重试',
                ),
              ),
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ErrorBanner(message: session.error!, onRetry: _refresh),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _createProject,
                      icon: const Icon(Icons.add),
                      label: const Text('新建项目'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码加入'),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _joinByCode,
                icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                label: const Text('输入邀请码加入'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouch),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SectionTitle(
              title: '我的项目',
              subtitle: projects.isEmpty ? null : '共 ${projects.length} 个项目',
            ),
            if (projects.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.line(context)),
                ),
                child: EmptyState(
                  title: '还没有项目',
                  message: '新建一个项目开始录入余砖；\n或者扫工头的二维码加入已有项目。',
                  icon: Icons.grid_view_rounded,
                  actionLabel: '新建第一个项目',
                  onAction: _createProject,
                ),
              )
            else
              ...projects.map((JoinedProject project) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ProjectCard(
                      project: project,
                      onTap: () => _openProject(project),
                    ),
                  )),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.line(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline, size: 18, color: AppColors.sub(context)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '无需注册账号。换手机或清除应用数据后，需要重新扫描邀请码加入项目；项目库存与历史不受影响。',
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.sub(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final JoinedProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ProjectStats stats = project.stats;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  project.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Tag(
                label: project.isOwner ? '拥有者' : '成员',
                color: project.isOwner ? AppColors.primary : AppColors.sub(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('${stats.pieces}', style: numberStyle(context, size: 30)),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text('片可用', style: TextStyle(fontSize: 13, color: AppColors.sub(context))),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${stats.batches} 批次 · ${stats.lShapeBatches} 个 L 形',
                    style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats.lastActivityAt == null ? '暂无流水' : '最近 ${formatRelative(stats.lastActivityAt)}',
                    style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
