import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../widgets/common.dart';
import '../../widgets/tile_shape_preview.dart';
import '../movements/movement_detail_page.dart';

/// 原砖 vs 需求 vs 余料 三列对比 + 父子链 + 关联流水.
class TracePage extends StatefulWidget {
  const TracePage(
      {super.key, required this.api, required this.batchId, this.title});

  final ProjectApi api;
  final String batchId;
  final String? title;

  @override
  State<TracePage> createState() => _TracePageState();
}

class _TracePageState extends State<TracePage> {
  TraceData? _trace;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TraceData trace = await widget.api.trace(widget.batchId);
      if (!mounted) return;
      setState(() {
        _trace = trace;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(error);
      });
    }
  }

  static int _intOf(Map<String, dynamic>? map, String key) {
    final dynamic value = map?[key];
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static List<ShapeRect> _rectsOf(Map<String, dynamic>? map) {
    final dynamic geometry = map?['geometry'];
    if (geometry is Map) {
      final dynamic rects = geometry['rects'];
      if (rects is List) {
        return rects.map(ShapeRect.fromJson).toList(growable: false);
      }
    }
    final dynamic rects = map?['rects'];
    if (rects is List)
      return rects.map(ShapeRect.fromJson).toList(growable: false);
    return const <ShapeRect>[];
  }

  @override
  Widget build(BuildContext context) {
    final TraceData? trace = _trace;
    final String unit = widget.api.project.defaultUnit;

    return Scaffold(
      appBar: buildAppBar(
        context,
        widget.title == null ? '溯源对比' : '溯源 ${widget.title}',
        actions: <Widget>[
          IconButton(
              tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4, itemHeight: 140)
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                if (_error != null)
                  ErrorBanner(message: _error!, onRetry: _load),
                if (trace != null) ...<Widget>[
                  const SectionTitle(
                      title: '三列对比', subtitle: '原砖 → 本次需求 → 切后余料'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _CompareCard(
                          label: '原砖',
                          sizeText: formatSize(
                            _intOf(trace.comparison.original, 'width_mm'),
                            _intOf(trace.comparison.original, 'height_mm'),
                            unit,
                          ),
                          areaText: formatArea(
                              _intOf(trace.comparison.original, 'area_mm2')),
                          preview: TileShapePreview(
                            widthMm:
                                _intOf(trace.comparison.original, 'width_mm'),
                            heightMm:
                                _intOf(trace.comparison.original, 'height_mm'),
                            rects: _rectsOf(trace.comparison.original),
                            height: 96,
                            showDimensions: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _CompareCard(
                          label: '本次需求',
                          sizeText: trace.comparison.demand == null
                              ? '—'
                              : formatSize(
                                  _intOf(trace.comparison.demand, 'width_mm'),
                                  _intOf(trace.comparison.demand, 'length_mm'),
                                  unit,
                                ),
                          areaText: formatArea(
                              _intOf(trace.comparison.demand, 'area_mm2')),
                          preview: trace.comparison.demand == null
                              ? const _EmptyPreview()
                              : TileShapePreview(
                                  widthMm: _intOf(
                                      trace.comparison.demand, 'width_mm'),
                                  heightMm: _intOf(
                                      trace.comparison.demand, 'length_mm'),
                                  demand: ShapeRect(
                                    x: 0,
                                    y: 0,
                                    w: _intOf(
                                        trace.comparison.demand, 'width_mm'),
                                    h: _intOf(
                                        trace.comparison.demand, 'length_mm'),
                                  ),
                                  remnantMode: true,
                                  height: 96,
                                  showDimensions: false,
                                ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _CompareCard(
                          label: '切后余料',
                          sizeText: trace.comparison.remnant == null
                              ? '无'
                              : formatSize(
                                  _intOf(trace.comparison.remnant, 'width_mm'),
                                  _intOf(trace.comparison.remnant, 'height_mm'),
                                  unit,
                                ),
                          areaText: trace.comparison.remnant == null
                              ? '—'
                              : formatArea(
                                  _intOf(trace.comparison.remnant, 'area_mm2')),
                          preview: trace.comparison.remnant == null
                              ? const _EmptyPreview(label: '无余料')
                              : TileShapePreview(
                                  widthMm: _intOf(
                                      trace.comparison.remnant, 'width_mm'),
                                  heightMm: _intOf(
                                      trace.comparison.remnant, 'height_mm'),
                                  rects: _rectsOf(trace.comparison.remnant),
                                  remnantMode: true,
                                  height: 96,
                                  showDimensions: false,
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (trace.comparison.demand != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '切割方式：${trace.comparison.demand!['cut_option_label'] ?? '—'} · 余料处置：${trace.comparison.demand!['remnant_action_label'] ?? '—'}',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.sub(context)),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: '溯源链', subtitle: '点节点可跳到对应批次'),
                  _Chain(trace: trace, onOpen: _openNode),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: '批次信息'),
                  _row(context, '批次号', trace.batch.code),
                  _row(
                      context,
                      '形状',
                      trace.batch.isIrregular
                          ? '异形（多块拼成）'
                          : (trace.batch.isLShape ? 'L 形（含缺口）' : '矩形')),
                  _row(
                      context,
                      '当前尺寸',
                      formatSize(
                          trace.batch.widthMm, trace.batch.heightMm, unit)),
                  _row(context, '剩余片数',
                      '${trace.batch.quantity} / ${trace.batch.initialQuantity}'),
                  _row(
                      context,
                      '存放位置',
                      trace.batch.location.isEmpty
                          ? '—'
                          : trace.batch.location),
                  _row(context, '来源',
                      trace.batch.sourceType == 'cut' ? '切割余料' : '原始录入'),
                  _row(context, '创建时间', formatDateTime(trace.batch.createdAt)),
                  const SizedBox(height: AppSpacing.lg),
                  SectionTitle(
                      title: '关联流水', subtitle: '共 ${trace.movements.length} 条'),
                  if (trace.movements.isEmpty)
                    Text('暂无关联流水',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.sub(context)))
                  else
                    ...trace.movements.map(
                      (Movement movement) => Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.card(context),
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: AppColors.line(context)),
                        ),
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MovementDetailPage(
                                  api: widget.api, movement: movement),
                            ),
                          ),
                          title: Text(movement.typeLabel,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${formatDateTime(movement.createdAt)} · ${movement.batchCode}',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.sub(context)),
                          ),
                          trailing: Text(
                            movement.quantityDelta == 0
                                ? '—'
                                : '${movement.quantityDelta > 0 ? '+' : ''}${movement.quantityDelta}',
                            style: numberStyle(context, size: 16),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Future<void> _openNode(TraceNode node) async {
    if (node.id == widget.batchId) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TracePage(api: widget.api, batchId: node.id, title: node.code),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: AppColors.sub(context))),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13.5, height: 1.4))),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard(
      {required this.label,
      required this.sizeText,
      required this.areaText,
      required this.preview});

  final String label;
  final String sizeText;
  final String areaText;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sub(context))),
          const SizedBox(height: 4),
          preview,
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(sizeText, style: numberStyle(context, size: 13)),
          ),
          Text(areaText,
              style: TextStyle(fontSize: 11, color: AppColors.sub(context))),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({this.label = '无数据'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.disabled)),
      ),
    );
  }
}

class _Chain extends StatelessWidget {
  const _Chain({required this.trace, required this.onOpen});

  final TraceData trace;
  final ValueChanged<TraceNode> onOpen;

  @override
  Widget build(BuildContext context) {
    final List<TraceNode> nodes = trace.nodes;
    if (nodes.isEmpty) {
      return Text('暂无溯源链',
          style: TextStyle(fontSize: 13, color: AppColors.sub(context)));
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nodes.length * 2 - 1,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 4),
        itemBuilder: (BuildContext context, int index) {
          if (index.isOdd) {
            return Icon(Icons.arrow_forward,
                size: 18, color: AppColors.sub(context));
          }
          final TraceNode node = nodes[index ~/ 2];
          final bool current = node.isCurrent;
          return InkWell(
            onTap: () => onOpen(node),
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Container(
              width: 108,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: current
                    ? AppColors.accent(context).withValues(alpha: 0.10)
                    : AppColors.card(context),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: current
                      ? AppColors.accent(context)
                      : AppColors.line(context),
                  width: current ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(node.code,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.label(context))),
                  const SizedBox(height: 2),
                  Text(
                    '${node.widthMm}×${node.heightMm}',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.sub(context)),
                  ),
                  Text(
                    current ? '当前批次' : '${node.quantity} 片',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.sub(context)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
