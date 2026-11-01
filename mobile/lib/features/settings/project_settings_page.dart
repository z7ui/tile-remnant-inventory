import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../projects/invite_page.dart';

class ProjectSettingsPage extends StatefulWidget {
  const ProjectSettingsPage({
    super.key,
    required this.api,
    required this.project,
    required this.onChanged,
  });

  final ProjectApi api;
  final JoinedProject project;
  final VoidCallback onChanged;

  @override
  State<ProjectSettingsPage> createState() => _ProjectSettingsPageState();
}

class _ProjectSettingsPageState extends State<ProjectSettingsPage> {
  List<MemberInfo>? _members;
  bool _loadingMembers = false;
  String? _memberError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMembers();
    });
  }

  Future<void> _loadMembers() async {
    if (!widget.project.isOwner) return;
    setState(() => _loadingMembers = true);
    try {
      final List<MemberInfo> members = await widget.api.members();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
        _memberError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMembers = false;
        _memberError = errorMessage(error);
      });
    }
  }

  Future<void> _leave() async {
    final bool ok = await confirmDanger(
      context,
      title: '移除本项目关联？',
      message: '移除后本机看不到该项目的库存与流水，但项目数据仍保留在服务器上。再次加入需要新的邀请码。',
      confirmLabel: '移除关联',
    );
    if (!ok || !mounted) return;
    final Session session = SessionScope.of(context);
    try {
      await session.leaveProject(widget.project);
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _delete() async {
    final bool ok = await confirmDanger(
      context,
      title: '删除项目？',
      message: '删除后，所有成员将无法再进入这个项目。库存与流水记录会保留，但 App 里不再显示。',
      confirmLabel: '删除项目',
    );
    if (!ok || !mounted) return;
    final Session session = SessionScope.of(context);
    try {
      await session.deleteProject(widget.project);
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _removeMember(MemberInfo member) async {
    final bool ok = await confirmDanger(
      context,
      title: '移除 ${member.name}？',
      message: '该设备将立即失去本项目访问权限，需要重新扫码才能加入。库存与历史不受影响。',
      confirmLabel: '移除',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.removeMember(member.deviceId);
      await _loadMembers();
      if (mounted) showSnack(context, '已移除该设备');
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Session session = SessionScope.of(context);
    final JoinedProject project = widget.project;

    return Scaffold(
      appBar: buildAppBar(context, '项目设置'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.line(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(project.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Tag(label: project.isOwner ? '拥有者设备' : '成员设备', color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Tag(label: project.defaultUnit == 'cm' ? '默认 cm' : '默认 mm', color: AppColors.sub(context)),
                    const SizedBox(width: AppSpacing.sm),
                    Tag(label: '最小可用 ${project.minUsableMm}mm', color: AppColors.sub(context)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '库存 ${project.stats.pieces} 片 · ${project.stats.batches} 个批次 · ${project.stats.lShapeBatches} 个 L 形',
                  style: TextStyle(fontSize: 13, color: AppColors.sub(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle(title: '邀请与成员', subtitle: '邀请码长期有效，可撤销或重置'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.line(context)),
            ),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('邀请码 / 二维码'),
                  subtitle: Text(project.isOwner ? '给工友扫码加入' : '仅拥有者设备可查看'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: project.isOwner
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => InvitePage(project: project)),
                          )
                      : null,
                ),
                if (project.isOwner) ...<Widget>[
                  Divider(height: 1, color: AppColors.line(context)),
                  if (_loadingMembers)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
                    )
                  else if (_memberError != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: ErrorBanner(message: _memberError!, onRetry: _loadMembers),
                    )
                  else
                    ...(_members ?? const <MemberInfo>[]).map(
                      (MemberInfo member) => ListTile(
                        leading: Icon(member.isCurrent ? Icons.phone_android : Icons.devices_outlined),
                        title: Text(member.name),
                        subtitle: Text(
                          '${member.isOwner ? '拥有者' : '成员'} · 加入于 ${formatDateTime(member.joinedAt)}',
                          style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
                        ),
                        trailing: member.isOwner
                            ? null
                            : IconButton(
                                tooltip: '移除该设备',
                                onPressed: () => _removeMember(member),
                                icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
                              ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle(title: '设备与服务器'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.line(context)),
            ),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('服务器'),
                  subtitle: Text(session.serverUrl, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    tooltip: '复制地址',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: session.serverUrl));
                      if (mounted) showSnack(context, '服务器地址已复制');
                    },
                    icon: const Icon(Icons.copy, size: 20),
                  ),
                ),
                Divider(height: 1, color: AppColors.line(context)),
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('本机设备 ID'),
                  subtitle: Text(session.deviceId ?? '—', style: const TextStyle(fontSize: 12)),
                ),
                Divider(height: 1, color: AppColors.line(context)),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    '无账号体系：设备密钥保存在系统安全存储中。换手机或清除应用数据后需要重新扫码加入，没有项目恢复码。',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sub(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle(title: '危险操作'),
          if (!project.isOwner)
            SizedBox(
              height: AppSizes.minTouch,
              child: OutlinedButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: const Text('移除本项目关联', style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
              ),
            ),
          if (project.isOwner) ...<Widget>[
            SizedBox(
              height: AppSizes.minTouch,
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_forever, color: AppColors.danger),
                label: const Text('删除项目（软删除）', style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '拥有者不能退出项目，只能删除项目。',
              style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text('余砖管家 0.1.0', style: TextStyle(fontSize: 12, color: AppColors.disabled)),
          ),
        ],
      ),
    );
  }
}
