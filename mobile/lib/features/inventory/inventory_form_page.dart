import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/dimension_input.dart';
import '../../widgets/tile_shape_preview.dart';

/// Manual stock-in. Rectangles only — long, width, pieces.
class InventoryFormPage extends StatefulWidget {
  const InventoryFormPage(
      {super.key, required this.api, this.knownLocations = const <String>[]});

  final ProjectApi api;
  final List<String> knownLocations;

  @override
  State<InventoryFormPage> createState() => _InventoryFormPageState();
}

class _InventoryFormPageState extends State<InventoryFormPage> {
  final TextEditingController _length = TextEditingController();
  final TextEditingController _width = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _location = TextEditingController();
  // 三个输入框的焦点自己管：键盘上的「下一步」按顺序走 长边 → 短边 → 片数，
  // 连续入库后也要能把光标送回长边。
  final FocusNode _lengthFocus = FocusNode();
  final FocusNode _widthFocus = FocusNode();
  final FocusNode _quantityFocus = FocusNode();
  final TextEditingController _note = TextEditingController();

  String _unit = 'mm';
  String? _lengthError;
  String? _widthError;
  String? _formError;
  bool _submitting = false;
  bool _prefsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final Session session = SessionScope.of(context);
    _unit = session.prefs
        .unitFor(widget.api.project.id, widget.api.project.defaultUnit);
    final String? last = session.prefs.lastLocation(widget.api.project.id);
    if (last != null && last.isNotEmpty) _location.text = last;
  }

  @override
  void dispose() {
    _length.dispose();
    _width.dispose();
    _quantity.dispose();
    _location.dispose();
    _lengthFocus.dispose();
    _widthFocus.dispose();
    _quantityFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _lengthMm => parseLengthToMm(_length.text, _unit);
  int? get _widthMm => parseLengthToMm(_width.text, _unit);
  int get _pieces => int.tryParse(_quantity.text) ?? 1;

  void _swap() {
    final String value = _length.text;
    _length.text = _width.text;
    _width.text = value;
    setState(() {});
  }

  /// [stay] = true 时连续入库：入库成功后清空尺寸和片数，**保留存放位置**，
  /// 用户站在原地接着放下一块砖，不用退出重进。
  Future<void> _submit({required bool stay}) async {
    final String? lengthError = validateLength(_length.text, _unit);
    final String? widthError = validateLength(_width.text, _unit);
    if (lengthError != null || widthError != null) {
      setState(() {
        _lengthError = lengthError;
        _widthError = widthError;
      });
      return;
    }
    if (_pieces < 1) {
      setState(() => _formError = '片数至少为 1');
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });
    final Session session = SessionScope.of(context);
    final int submittedPieces = _pieces;
    final String submittedSize =
        formatSize(_widthMm ?? 0, _lengthMm ?? 0, _unit);
    try {
      await widget.api.createBatch(
        length: _length.text,
        width: _width.text,
        quantity: submittedPieces,
        unit: _unit,
        location: _location.text,
        note: _note.text,
      );
      await session.prefs.setUnit(widget.api.project.id, _unit);
      final String place = _location.text.trim();
      if (stay) {
        // 连续录入：这一摞砖基本都在同一处，记住它
        if (place.isNotEmpty) {
          await session.prefs.setLastLocation(widget.api.project.id, place);
        }
      } else {
        // 「并返回」意味着这次录入收工了。清掉记忆，下次进来位置是空的——
        // 否则标题下面挂着上次的地点，用户会以为已经填好，直接点确认就存错位置。
        await session.prefs.setLastLocation(widget.api.project.id, '');
      }
      if (!mounted) return;

      if (stay) {
        // 尺寸清空，位置留着——同一摞砖通常放在同一个地方
        setState(() {
          _submitting = false;
          _length.clear();
          _width.clear();
          _quantity.text = '1';
          _note.clear();
          _lengthError = null;
          _widthError = null;
          _formError = null;
        });
        // 清空后光标留在短边会让人以为该先填短边，其实顺序是长边优先
        _lengthFocus.requestFocus();
        showSnack(
          context,
          '已入库 $submittedPieces 片 · $submittedSize${place.isEmpty ? '' : ' · $place'}',
        );
        return;
      }

      await showSavedCard(
        context,
        title: '已入库 $submittedPieces 片',
        subtitle: '$submittedSize${place.isEmpty ? '' : ' · $place'}',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int lengthMm = _lengthMm ?? 0;
    final int widthMm = _widthMm ?? 0;
    final bool hasPreview = lengthMm > 0 && widthMm > 0;
    final String hint = hasPreview
        ? '${formatSize(widthMm, lengthMm, _unit)} · ${formatArea(lengthMm * widthMm)} × $_pieces 片'
        : '只支持矩形余砖，长和宽都要填';

    return Scaffold(
      appBar: buildAppBar(context, '录入余砖'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
                    AppSpacing.lg, AppSpacing.xxl),
                children: <Widget>[
                  DimensionInput(
                    lengthFocus: _lengthFocus,
                    widthFocus: _widthFocus,
                    onLengthSubmitted: () => _widthFocus.requestFocus(),
                    onWidthSubmitted: () => _quantityFocus.requestFocus(),
                    lengthController: _length,
                    widthController: _width,
                    unit: _unit,
                    lengthError: _lengthError,
                    widthError: _widthError,
                    onSwap: _swap,
                    autofocus: true,
                    onUnitChanged: (String value) => setState(() {
                      _unit = value;
                      _lengthError = null;
                      _widthError = null;
                    }),
                  ),
                  // 长/宽/片数是最关键的三项，必须能在一屏里填完。
                  // 之前片数排在提示框后面，键盘一弹就被顶到屏幕外，点都点不到。
                  const SizedBox(height: AppSpacing.md),
                  const SectionTitle(title: '片数'),
                  QuantityInput(
                      controller: _quantity, onChanged: (_) => setState(() {})),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.line(context)),
                    ),
                    child: hasPreview
                        ? TileShapePreview(
                            widthMm: widthMm,
                            heightMm: lengthMm,
                            height: 140,
                            caption: '录入的是整块矩形余砖（不含缺口）',
                          )
                        : Row(
                            children: <Widget>[
                              // 原来是 Icons.crop_square——一个空心方框，看着像「可选的选项框」，
                              // 其实只是装饰，用户点了当然没反应。换成信息图标，明确是提示。
                              Icon(Icons.info_outline,
                                  size: 18, color: AppColors.sub(context)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '主动录入只支持矩形；异形（L 形）余料只能来自切割后入库。',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: AppColors.sub(context)),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: '存放位置', subtitle: '方便以后找砖，可留空'),
                  TextField(
                    controller: _location,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      hintText: '例如：阳台 / 储物间 / 3 栋 1802',
                      counterText: '',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  if (widget.knownLocations.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: widget.knownLocations
                          .take(6)
                          .map(
                            (String location) => ActionChip(
                              label: Text(location),
                              onPressed: () =>
                                  setState(() => _location.text = location),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: '备注', subtitle: '可选，例如色号、批次'),
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    maxLength: 200,
                    decoration:
                        const InputDecoration(hintText: '例如：同批次 800×800 抛光砖'),
                  ),
                  if (_formError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    ErrorBanner(message: _formError!),
                  ],
                ],
              ),
            ),
            // 键盘弹出时收起底部按钮：它贴着键盘占掉近 80dp，
            // 把「片数」等输入框挤出可视区。收起键盘后按钮自动回来。
            if (MediaQuery.of(context).viewInsets.bottom == 0)
              BottomActionBar(
                hint: hint,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        height: AppSizes.primaryButton,
                        child: OutlinedButton(
                          onPressed:
                              _submitting ? null : () => _submit(stay: true),
                          child: const Text('连续入库'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: '确认入库并返回',
                        loading: _submitting,
                        onPressed: () => _submit(stay: false),
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
