import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'confirm_usage_page.dart';
import '../trace/trace_page.dart';

class MatchPage extends StatefulWidget {
  const MatchPage({super.key, required this.api, required this.reloadToken, required this.onChanged});

  final ProjectApi api;
  final int reloadToken;
  final VoidCallback onChanged;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  final TextEditingController _length = TextEditingController();
  final TextEditingController _width = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '1');

  String _unit = 'mm';
  String? _lengthError;
  String? _widthError;
  String? _error;
  bool _loading = false;
  bool _prefsLoaded = false;
  MatchResult? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final Session session = SessionScope.of(context);
    _unit = session.prefs.unitFor(widget.api.project.id, widget.api.project.defaultUnit);
  }

  @override
  void didUpdateWidget(covariant MatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken && _result != null) {
      _runMatch(silent: true);
    }
  }

  @override
  void dispose() {
    _length.dispose();
    _width.dispose();
    _quantity.dispose();
    super.dispose();
  }

  int get _pieces => int.tryParse(_quantity.text) ?? 1;

  void _swap() {
    final String value = _length.text;
    _length.text = _width.text;
    _width.text = value;
    setState(() {});
  }

  Future<void> _runMatch({bool silent = false}) async {
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
      setState(() => _error = '需求数量至少为 1 片');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _lengthError = null;
      _widthError = null;
    });
    try {
      final MatchResult result = await widget.api.match(
        length: _length.text,
        width: _width.text,
        quantity: _pieces,
        unit: _unit,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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

  Future<void> _use(MatchCandidate candidate) async {
    final int take = math.min(_pieces, math.min(candidate.maxPieces, candidate.batch.quantity));
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConfirmUsagePage(
          api: widget.api,
          candidate: candidate,
          demandLengthMm: parseLengthToMm(_length.text, _unit) ?? 0,
          demandWidthMm: parseLengthToMm(_width.text, _unit) ?? 0,
          quantity: take,
          unit: _unit,
        ),
      ),
    );
    if (done != true || !mounted) return;
    widget.onChanged();
    final int remaining = _pieces - take;
    if (remaining <= 0) {
      setState(() => _result = null);
      showSnack(context, '需求已全部确认使用');
      return;
    }
    _quantity.text = '$remaining';
    showSnack(context, '还剩 $remaining 片待匹配');
    await _runMatch(silent: true);
  }

  Future<void> _openTrace(MatchCandidate candidate) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TracePage(api: widget.api, batchId: candidate.batch.id, title: candidate.batch.code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MatchResult? result = _result;

    return Scaffold(
      appBar: buildAppBar(context, '快速匹配'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
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
                const SectionTitle(title: '需要多大', subtitle: '允许旋转 90°，需求必须被余砖完全覆盖'),
                DimensionInput(
                  lengthController: _length,
                  widthController: _width,
                  unit: _unit,
                  lengthError: _lengthError,
                  widthError: _widthError,
                  onSwap: _swap,
                  onUnitChanged: (String value) => setState(() => _unit = value),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Text('数量', style: TextStyle(fontSize: 13, color: AppColors.sub(context))),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: QuantityInput(controller: _quantity, onChanged: (_) => setState(() {}))),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: '开始匹配',
                  icon: Icons.search,
                  loading: _loading,
                  onPressed: () => _runMatch(),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!, onRetry: () => _runMatch()),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_loading) const SkeletonList(itemCount: 3, itemHeight: 220),
          if (!_loading && result != null) _buildResult(result),
          if (!_loading && result == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.line(context)),
              ),
              child: const EmptyState(
                title: '输入尺寸开始匹配',
                message: '例如需要 800×600mm 一块，系统会按浪费面积从少到多排序，并给出切割与余料预览。',
                icon: Icons.search,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(MatchResult result) {
    final bool shortage = result.unfulfilledQuantity > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: (shortage ? AppColors.warning : AppColors.success).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: (shortage ? AppColors.warning : AppColors.success).withValues(alpha: 0.32)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(shortage ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 20, color: shortage ? AppColors.warning : AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  shortage
                      ? '找到 ${result.candidates.length} 个候选，但还差 ${result.unfulfilledQuantity} 片，建议先录入更多余砖。'
                      : '找到 ${result.candidates.length} 个候选，可满足 ${result.demand.quantity} 片需求。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: shortage ? AppColors.warning : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (result.allocation.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '建议拆分：${result.allocation.map((AllocationSuggestion a) => '#${a.batchNo.toString().padLeft(4, '0')} × ${a.quantity}').join('，')}',
            style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ...result.candidates.map(
          (MatchCandidate candidate) => _CandidateCard(
            candidate: candidate,
            unit: _unit,
            demandQuantity: _pieces,
            onUse: () => _use(candidate),
            onTrace: () => _openTrace(candidate),
          ),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.unit,
    required this.demandQuantity,
    required this.onUse,
    required this.onTrace,
  });

  final MatchCandidate candidate;
  final String unit;
  final int demandQuantity;
  final VoidCallback onUse;
  final VoidCallback onTrace;

  @override
  Widget build(BuildContext context) {
    final Batch batch = candidate.batch;
    final int take = math.min(demandQuantity, math.min(candidate.maxPieces, batch.quantity));
    final String utilization = '${(candidate.utilization * 100).toStringAsFixed(0)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(batch.code, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub(context))),
              const SizedBox(width: 6),
              if (batch.isLShape) Tag(label: 'L 形', color: AppColors.remnant) else Tag(label: '矩形', color: AppColors.primary),
              const SizedBox(width: 4),
              Tag(label: '剩 ${batch.quantity} 片', color: AppColors.sub(context)),
              const Spacer(),
              if (candidate.rotation == 90) Tag(label: '旋转 90°', color: AppColors.warning, icon: Icons.rotate_90_degrees_ccw),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TileShapePreview(
            widthMm: batch.widthMm,
            heightMm: batch.heightMm,
            rects: batch.rects,
            demand: candidate.placement,
            remnantMode: true,
            showCutLines: true,
            height: 168,
            showLegend: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              _Metric(label: '原砖', value: formatSize(batch.widthMm, batch.heightMm, unit)),
              _Metric(label: '浪费', value: formatArea(candidate.wasteMm2)),
              _Metric(label: '利用率', value: utilization),
              _Metric(label: '可切', value: '${candidate.maxPieces} 片'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            children: candidate.cutOptions
                .map(
                  (CutOptionPreview option) => Tag(
                    label: option.feasible ? option.label : '${option.label}·不可用',
                    color: option.feasible ? AppColors.primary : AppColors.disabled,
                    icon: option.feasible ? Icons.content_cut : Icons.block,
                  ),
                )
                .toList(growable: false),
          ),
          if (candidate.remnant != null && candidate.remnant!.belowThreshold)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '余料最小边小于项目阈值，入库后可能不好再利用。',
                style: TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTrace,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('溯源'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: AppSizes.minTouch,
                  child: FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.check, size: 20),
                    label: Text(take > 1 ? '使用这块（$take 片）' : '使用这块'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.sub(context))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.label(context),
                fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
