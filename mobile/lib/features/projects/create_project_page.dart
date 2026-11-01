import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
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

  String _unit = 'mm';
  String? _nameError;

  /// 同名项目已有几个（只是提示，不阻止创建）
  int _sameNameCount = 0;
  String? _formError;
  bool _checking = false;
  bool _submitting = false;
  Timer? _debounce;
  String? _lastChecked;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _checkName();
    });
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _minUsable.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _checkName);
    if (_nameError != null) setState(() => _nameError = null);
  }

  Future<void> _checkName() async {
    final String value = _name.text.trim();
    if (value.length < 2) return;
    if (_lastChecked == value) return;
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      final Session session = SessionScope.of(context);
      final dynamic json = await session.api.get(
        '/api/projects/name-available',
        query: <String, String>{'name': value},
        withDeviceSecret: true,
      );
      _lastChecked = value;
      // 项目名允许重复：唯一性由创建时分配的特征码保证。
      // 这里只提示「已经有几个同名的」，让你知道会多出一个新的，
      // 而不是拦住你——也正因如此，枚举项目名得不到任何信息。
      final int same = (json as Map)['same_name_count'] as int? ?? 0;
      if (!mounted) return;
      setState(() {
        _nameError = null;
        _sameNameCount = same;
        _checking = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        // 断网时不要拦住提交：让最终的服务端请求去报错，那里文案更准确。
        // 其它错误（401/403/500）也不能静默吞掉，否则用户只会看到「按钮没反应」。
        if (!e.isNetwork) _formError = '名称预检查失败（${e.message}），可直接点「创建项目」重试。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _formError = '名称预检查失败（$error），可直接点「创建项目」重试。';
      });
    }
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
    if (_nameError != null) {
      // 这里曾经是静默 return：按钮点了毫无反应，用户根本不知道卡在哪。
      _fail(_nameError!);
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
          await session.createProject(name, _unit, minUsable);
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
      setState(() {
        _submitting = false;
        if (error is ApiException && error.code == 'project_name_taken') {
          _nameError = error.message;
        }
      });
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
                  const SectionTitle(
                      title: '项目信息', subtitle: '同名也可以建；创建后会分配一个 4 位码用来区分'),
                  TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: '项目名称',
                      hintText: '例如：金域蓝湾 3 栋 1802',
                      counterText: '',
                      errorText: _nameError,
                      errorMaxLines: 2,
                      suffixIcon: _checking
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : (_nameError == null && _lastChecked != null
                              ? const Icon(Icons.check_circle_outline,
                                  color: AppColors.success)
                              : null),
                    ),
                  ),
                  if (_sameNameCount > 0 && _nameError == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 2),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.info_outline,
                              size: 15, color: AppColors.sub(context)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '已有 $_sameNameCount 个同名项目。继续创建会生成新项目，'
                              '靠 4 位码区分，不会混在一起。',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: AppColors.sub(context)),
                            ),
                          ),
                        ],
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
                    selected: <String>{_unit},
                    onSelectionChanged: (Set<String> selection) =>
                        setState(() => _unit = selection.first),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '录入时只填数字，按这里选的单位解析。',
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
