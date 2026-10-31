import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';

/// Full screen invitation: QR + code + copy actions.
class InvitePage extends StatefulWidget {
  const InvitePage({super.key, required this.project, this.isNew = false});

  final JoinedProject project;
  final bool isNew;

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  InviteInfo? _invite;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final Session session = SessionScope.of(context);
    final ProjectApi api = ProjectApi(session, widget.project);
    try {
      final InviteInfo invite = await api.invite();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.project.isOwner ? errorMessage(error) : '只有项目拥有者设备可以查看邀请码。';
      });
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '$label已复制');
  }

  Future<void> _revoke() async {
    final bool ok = await confirmDanger(
      context,
      title: '撤销邀请码？',
      message: '撤销后旧邀请码立即失效，已经加入的设备不受影响。',
      confirmLabel: '撤销',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final InviteInfo invite = await ProjectApi(SessionScope.of(context), widget.project).revokeInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
      showSnack(context, '邀请码已撤销');
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final bool ok = await confirmDanger(
      context,
      title: '重置邀请码？',
      message: '会生成新邀请码，旧码立即失效。已加入的设备不受影响。',
      confirmLabel: '重置',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final InviteInfo invite = await ProjectApi(SessionScope.of(context), widget.project).resetInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
      showSnack(context, '已生成新的邀请码');
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context,
        widget.isNew ? '项目已创建' : '邀请工友加入',
        actions: <Widget>[
          if (widget.isNew)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  if (widget.isNew)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '「${widget.project.name}」创建成功，把下面的二维码给工友扫。',
                                style: const TextStyle(fontSize: 13.5, color: AppColors.success, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null) ErrorBanner(message: _error!, onRetry: _load),
                  if (_error == null && _invite != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.line(context)),
                      ),
                      child: Column(
                        children: <Widget>[
                          if (_invite!.isActive && _invite!.qrPayload != null)
                            QrImageView(
                              data: _invite!.qrPayload!,
                              version: QrVersions.auto,
                              size: 236,
                              backgroundColor: Colors.white,
                              gapless: true,
                            )
                          else
                            SizedBox(
                              height: 236,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.link_off, size: 48, color: AppColors.disabled),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text('邀请码已撤销', style: TextStyle(color: AppColors.sub(context))),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            _invite!.isActive ? '邀请码' : '已失效',
                            style: TextStyle(fontSize: 13, color: AppColors.sub(context)),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          SelectableText(
                            _invite!.code ?? '—',
                            style: TextStyle(
                              fontSize: 32,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w700,
                              color: AppColors.label(context),
                              fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _invite!.code == null ? null : () => _copy(_invite!.code!, '邀请码'),
                                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                                  label: const Text('复制邀请码'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _invite!.joinUrl == null ? null : () => _copy(_invite!.joinUrl!, '加入链接'),
                                  icon: const Icon(Icons.link, size: 18),
                                  label: const Text('复制链接'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.line(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('邀请码长期有效', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.label(context))),
                          const SizedBox(height: 6),
                          Text(
                            '不自动过期，可随时撤销或重置。没有项目恢复码：工友换手机或清除应用数据后，需要重新扫码加入。',
                            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sub(context)),
                          ),
                        ],
                      ),
                    ),
                    if (widget.project.isOwner) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy || !_invite!.isActive ? null : _revoke,
                              child: const Text('撤销邀请码'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy ? null : _reset,
                              child: const Text('重置邀请码'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (widget.isNew)
                    PrimaryButton(
                      label: '开始使用',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
      ),
    );
  }
}
