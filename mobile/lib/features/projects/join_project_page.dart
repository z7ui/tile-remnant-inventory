import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../settings/server_setup_page.dart';
import 'qr_scan_page.dart';

/// Join by invitation code, optionally switching the server encoded in a QR.
class JoinProjectPage extends StatefulWidget {
  const JoinProjectPage({super.key, this.initialCode, this.initialServer});

  final String? initialCode;
  final String? initialServer;

  @override
  State<JoinProjectPage> createState() => _JoinProjectPageState();
}

class _JoinProjectPageState extends State<JoinProjectPage> {
  late final TextEditingController _code;
  late String _server;
  String? _error;
  bool _submitting = false;
  bool _resolvedServer = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.initialCode ?? '');
    _server = widget.initialServer ?? AppConfig.defaultBaseUrl;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedServer) return;
    _resolvedServer = true;
    if (widget.initialServer == null) {
      _server = SessionScope.maybeOf(context)?.serverUrl ?? AppConfig.defaultBaseUrl;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final String? payload = await scanInviteCode(context);
    if (payload == null || !mounted) return;
    final Session session = SessionScope.of(context);
    try {
      final JoinedProject project = await session.joinProjectFromPayload(payload);
      if (!mounted) return;
      Navigator.of(context).pop(project);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorMessage(error));
    }
  }

  Future<void> _join() async {
    final String code = _code.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = '请输入完整的邀请码（6 位以上字母数字）');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final Session session = SessionScope.of(context);
    try {
      final JoinedProject project = await session.joinProject(code, server: _server);
      if (!mounted) return;
      Navigator.of(context).pop(project);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, '加入项目'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  Text('输入邀请码', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '工头可以在「项目 → 邀请工友」里看到邀请码和二维码。',
                    style: TextStyle(fontSize: 13, color: AppColors.sub(context)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _code,
                    autofocus: widget.initialCode == null,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    style: const TextStyle(fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(hintText: 'ABCD2345EF'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫描二维码'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionTitle(title: '服务器', subtitle: '二维码里会自动带上，通常不用改'),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.line(context)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.dns_outlined, size: 20, color: AppColors.sub(context)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _server,
                            style: const TextStyle(fontSize: 13.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final String? url = await Navigator.of(context).push<String>(
                              MaterialPageRoute<String>(
                                builder: (_) => ServerSetupPage(initialUrl: _server),
                              ),
                            );
                            if (url != null && mounted) setState(() => _server = url);
                          },
                          child: const Text('修改'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.line(context)),
                    ),
                    child: Text(
                      '加入后本项目会长期保留在手机上，下次打开无需再次扫码。同一台手机可以加入多个项目。',
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sub(context)),
                    ),
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: PrimaryButton(label: '加入项目', loading: _submitting, onPressed: _join),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
