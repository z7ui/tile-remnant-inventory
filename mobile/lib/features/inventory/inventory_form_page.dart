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
  const InventoryFormPage({super.key, required this.api, this.knownLocations = const <String>[]});

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
    _unit = session.prefs.unitFor(widget.api.project.id, widget.api.project.defaultUnit);
    final String? last = session.prefs.lastLocation(widget.api.project.id);
    if (last != null && last.isNotEmpty) _location.text = last;
  }

  @override
  void dispose() {
    _length.dispose();
    _width.dispose();
    _quantity.dispose();
    _location.dispose();
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

  Future<void> _submit() async {
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
    try {
      await widget.api.createBatch(
        length: _length.text,
        width: _width.text,
        quantity: _pieces,
        unit: _unit,
        location: _location.text,
        note: _note.text,
      );
      await session.prefs.setUnit(widget.api.project.id, _unit);
      if (_location.text.trim().isNotEmpty) {
        await session.prefs.setLastLocation(widget.api.project.id, _location.text.trim());
      }
      if (!mounted) return;
      final String place = _location.text.trim();
      await showSavedCard(
        context,
        title: '已入库 $_pieces 片',
        subtitle: '${formatSize(_widthMm ?? 0, _lengthMm ?? 0, _unit)}${place.isEmpty ? '' : ' · $place'}',
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
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  DimensionInput(
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
                              Icon(Icons.crop_square, color: AppColors.sub(context)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '主动录入只支持矩形；异形（L 形）余料只能来自切割后入库。',
                                  style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.sub(context)),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: '片数'),
                  QuantityInput(controller: _quantity, onChanged: (_) => setState(() {})),
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
                              onPressed: () => setState(() => _location.text = location),
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
                    decoration: const InputDecoration(hintText: '例如：同批次 800×800 抛光砖'),
                  ),
                  if (_formError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    ErrorBanner(message: _formError!),
                  ],
                ],
              ),
            ),
            BottomActionBar(
              hint: hint,
              child: PrimaryButton(label: '确认入库', loading: _submitting, onPressed: _submit),
            ),
          ],
        ),
      ),
    );
  }
}
