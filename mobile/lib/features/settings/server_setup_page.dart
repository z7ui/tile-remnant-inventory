import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';

/// Server address form. Pops with the new URL so the caller can persist it
/// (either on the boot screen or inside settings with a confirmation).
class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    String initial = widget.initialUrl ?? '';
    if (initial.isEmpty) {
      initial = AppConfig.defaultBaseUrl;
    }
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _valid(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' && AppConfig.isLocalHost(uri);
  }

  void _submit() {
    final String value = _controller.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!_valid(value)) {
      setState(() => _error = '请填写完整的 https:// 地址（例如 https://tiles.example.com）');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, '服务器地址'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('数据存放在你自己的博客云主机上', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '填写服务器地址（HTTPS 域名）。为保护数据只接受 HTTPS；http 仅用于本机调试。',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.sub(context)),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://tiles.example.com',
                  errorText: _error,
                  errorMaxLines: 2,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: '保存并使用', onPressed: _submit),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: AppColors.line(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 18, color: AppColors.sub(context)),
                        const SizedBox(width: 6),
                        Text('更换服务器会清空本机项目', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.label(context))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '设备身份与项目令牌按服务器签发。更换域名后需要重新扫码加入项目，但项目数据仍保留在原服务器。',
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.sub(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '当前默认：${SessionScope.maybeOf(context)?.serverUrl ?? AppConfig.defaultBaseUrl}',
                style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
