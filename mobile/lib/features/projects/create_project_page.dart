import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import 'invite_page.dart';

class CreateProjectPage extends StatefulWidget {
  const CreateProjectPage({super.key});

  @override
  State<CreateProjectPage> createState() => _CreateProjectPageState();
}

class _CreateProjectPageState extends State<CreateProjectPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _minUsable = TextEditingController(text: '50');
  final FocusNode _nameFocus = FocusNode();

  /// 默认单位必须手动选：不给预选，避免用户没注意就用错了单位录一堆砖
  String? _unit;
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _minUsable.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// 失败统一走这里：既写进页内 banner，也弹一次底部提示。
  /// 光靠 banner 不够——它在 ListView 中间，用户停在按钮那一屏时根本看不到，
  /// 体感就是「点了没反应」。
  void _fail(String message, {bool focusName = false}) {
    setState(() => _formError = message);
    if (focusName) _nameFocus.requestFocus();
    showSnack(context, message, error: true);
  }

  Future<void> _submit() async {
    final String name = _name.text.trim();
    if (name.length < 2) {
      _fail('请填写项目名称（至少 2 个字符）', focusName: true);
      return;
    }
    final String? unit = _unit;
    if (unit == null) {
      _fail('请先选择默认单位：毫米或厘米');
      return;
    }

    final int? minUsable = int.tryParse(_minUsable.text.trim());
    if (minUsable == null || minUsable < 0 || minUsable > 5000) {
      _fail('最小可用尺寸需为 0–5000mm 的整数');
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });
    final Session session = SessionScope.of(context);
    try {
      final JoinedProject project =
          await session.createProject(name, unit, minUsable);
      if (!mounted) return;
      await session.refreshProjects();
      if (!mounted) return;
      final JoinedProject fresh = session.projects.firstWhere(
        (JoinedProject p) => p.id == project.id,
        orElse: () => project,
      );
      setState(() => _submitting = false);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
            builder: (_) => InvitePage(project: fresh, isNew: true)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _fail(errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, '新建项目'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  const SectionTitle(title: '项目信息'),
                  TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: '项目名称',
                      hintText: '例如：金域蓝湾 3 栋 1802',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('默认单位',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.sub(context))),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(value: 'mm', label: Text('毫米 mm')),
                      ButtonSegment<String>(value: 'cm', label: Text('厘米 cm')),
                    ],
                    emptySelectionAllowed: true,
                    selected: _unit == null ? <String>{} : <String>{_unit!},
                    onSelectionChanged: (Set<String> selection) => setState(
                        () =>
                            _unit = selection.isEmpty ? null : selection.first),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _unit == null
                        ? '必须选一个，否则录库存时不知道 60 是 60mm 还是 60cm。'
                        : '录入时只填数字，按这里选的单位解析。',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.sub(context)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _minUsable,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '最小可用尺寸（mm）',
                      helperText: '任一边小于该值时，余料入库会给出提示',
                      suffixText: 'mm',
                    ),
                  ),
                  if (_formError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    ErrorBanner(message: _formError!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.line(context)),
                    ),
                    child: Text(
                      '创建后会生成长期有效的邀请码和二维码，工友扫码即可加入。邀请码可随时撤销或重置。',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.sub(context)),
                    ),
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: PrimaryButton(
                  label: '创建项目', loading: _submitting, onPressed: _submit),
            ),
          ],
        ),
      ),
    );
  }
}
