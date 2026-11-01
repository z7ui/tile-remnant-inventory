import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/tile_shape_preview.dart';
import '../trace/trace_page.dart';

/// Two step confirmation: cut option → remnant handling, with a live preview.
class ConfirmUsagePage extends StatefulWidget {
  const ConfirmUsagePage({
    super.key,
    required this.api,
    required this.candidate,
    required this.demandLengthMm,
    required this.demandWidthMm,
    required this.quantity,
    required this.unit,
  });

  final ProjectApi api;
  final MatchCandidate candidate;
  final int demandLengthMm;
  final int demandWidthMm;
  final int quantity;
  final String unit;

  @override
  State<ConfirmUsagePage> createState() => _ConfirmUsagePageState();
}

class _ConfirmUsagePageState extends State<ConfirmUsagePage> {
  late String _cutOption;
  late String _remnantAction;
  late String _idempotencyKey;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;
  bool _prefsLoaded = false;

  Batch get _batch => widget.candidate.batch;

  CutOptionPreview? get _preview => widget.candidate.previewFor(_cutOption);

  @override
  void initState() {
    super.initState();
    _cutOption = widget.candidate.cutOption;
    _remnantAction = 'store';
    _idempotencyKey = newIdempotencyKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final UserPrefs prefs = SessionScope.of(context).prefs;
    final String projectId = widget.api.project.id;
    final String savedCut = prefs.cutOptionFor(projectId);
    final CutOptionPreview? saved = widget.candidate.previewFor(savedCut);
    if (saved != null && saved.feasible) _cutOption = savedCut;
    _remnantAction = prefs.remnantActionFor(projectId);
  }

  Future<void> _confirm() async {
    if (_submitting || _submitted) return;
    final CutOptionPreview? preview = _preview;
    if (preview == null || !preview.feasible) {
      setState(() => _error = '当前切法放不下，请换一种切法。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final Session session = SessionScope.of(context);
    try {
      final UsageResult result = await widget.api.confirm(
        idempotencyKey: _idempotencyKey,
        length: '${widget.demandLengthMm}',
        width: '${widget.demandWidthMm}',
        quantity: widget.quantity,
        unit: 'mm',
        allocations: <Map<String, dynamic>>[
          <String, dynamic>{
            'batch_id': _batch.id,
            'quantity': widget.quantity,
            'cut_option': _cutOption,
            'remnant_action': preview.remnant == null ? null : _remnantAction,
          },
        ],
        note: '',
      );
      await session.prefs.setCutOption(widget.api.project.id, _cutOption);
      await session.prefs
          .setRemnantAction(widget.api.project.id, _remnantAction);
      if (!mounted) return;
      _submitted = true;
      setState(() => _submitting = false);
      await _showSuccess(result);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _showSuccess(UsageResult result) async {
    final UsageLine? line = result.lines.isEmpty ? null : result.lines.first;
    final Batch? produced = line?.remnantBatch;
    final bool discarded = line?.remnantActionLabel == '丢弃';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.check_circle,
                      color: AppColors.success, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      result.replayed
                          ? '已确认（重复提交已拦截）'
                          : '已确认使用 ${widget.quantity} 片',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _KeyValue(label: '扣减批次', value: _batch.code),
              _KeyValue(label: '切割方式', value: line?.cutOptionLabel ?? '—'),
              _KeyValue(
                  label: '余料处置',
                  value: line?.remnantActionLabel ??
                      (line?.remnant == null ? '无余料' : '—')),
              if (produced != null)
                _KeyValue(
                  label: '余料入库',
                  value:
                      '${produced.code} · ${formatSize(produced.widthMm, produced.heightMm, widget.unit)} · ${produced.quantity} 片',
                ),
              if (discarded) const _KeyValue(label: '余料', value: '已丢弃（流水已记录）'),
              const SizedBox(height: AppSpacing.md),
              if (produced != null)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TracePage(
                            api: widget.api,
                            batchId: produced.id,
                            title: produced.code),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('查看余料溯源'),
                ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: '完成',
                // 只关这张卡片；确认页由 _confirm 里的 pop(true) 负责关。
                // 之前这里也 pop 了一次页面，导致连着关掉匹配页、直接退回主页，
                // 多块砖匹配时看不到「还剩 N 片待匹配」。
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CutOptionPreview? preview = _preview;
    final Remnant? remnant = preview?.remnant;
    final int remaining = _batch.quantity - widget.quantity;
    final int pieceArea = widget.demandLengthMm * widget.demandWidthMm;
    final String unit = widget.unit;

    return Scaffold(
      appBar: buildAppBar(context, '确认使用'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
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
                        Row(
                          children: <Widget>[
                            Text(_batch.code,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.sub(context))),
                            const SizedBox(width: 6),
                            if (_batch.isIrregular)
                              Tag(label: '异形', color: AppColors.warning)
                            else if (_batch.isLShape)
                              Tag(label: 'L 形', color: AppColors.remnant)
                            else
                              Tag(label: '矩形', color: AppColors.primary),
                            const Spacer(),
                            Text('剩 ${_batch.quantity} 片',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.sub(context))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatSize(widget.demandWidthMm, widget.demandLengthMm, unit)} × ${widget.quantity} 片',
                          style: numberStyle(context, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (preview != null && preview.feasible)
                    TileShapePreview(
                      widthMm: _batch.widthMm,
                      heightMm: _batch.heightMm,
                      rects: _batch.rects,
                      demand: preview.placement,
                      remnantMode: true,
                      showCutLines: true,
                      height: 220,
                      showLegend: true,
                      caption: remnant == null ? '整砖使用，无余料' : null,
                    )
                  else
                    Container(
                      height: 140,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.line(context)),
                      ),
                      child: Text('当前切法无法切出该尺寸',
                          style: TextStyle(color: AppColors.sub(context))),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  if (remnant == null)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.check_circle_outline,
                              color: AppColors.success, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '整砖使用，无余料，无需选择切割方式与余料处置。',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.success,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...<Widget>[
                    const SectionTitle(
                        title: '1. 选择切割方式', subtitle: '图示为俯视图，虚线是刀路'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: _CutOptionCard(
                            option:
                                widget.candidate.previewFor('long_side_cut'),
                            batch: _batch,
                            selected: _cutOption == 'long_side_cut',
                            onTap: () =>
                                setState(() => _cutOption = 'long_side_cut'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _CutOptionCard(
                            option:
                                widget.candidate.previewFor('short_side_cut'),
                            batch: _batch,
                            selected: _cutOption == 'short_side_cut',
                            onTap: () =>
                                setState(() => _cutOption = 'short_side_cut'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionTitle(
                        title: '2. 余料处置', subtitle: '入库会生成新的余料批次，可继续使用'),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _RemnantOptionCard(
                            label: '直接入库',
                            hint: remnant.isLShape ? '按 L 形异形库存入库' : '按矩形库存入库',
                            icon: Icons.inventory_2_outlined,
                            color: AppColors.primary,
                            remnant: remnant,
                            selected: _remnantAction == 'store',
                            onTap: () =>
                                setState(() => _remnantAction = 'store'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _RemnantOptionCard(
                            label: '丢弃',
                            hint: '不入库，仅记录流水',
                            icon: Icons.delete_outline,
                            color: AppColors.danger,
                            remnant: remnant,
                            selected: _remnantAction == 'discard',
                            onTap: () =>
                                setState(() => _remnantAction = 'discard'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionTitle(title: '尺寸与面积对比'),
                    Row(
                      children: <Widget>[
                        _CompareCell(
                            label: '原砖',
                            size: formatSize(
                                _batch.widthMm, _batch.heightMm, unit),
                            area: formatArea(_batch.areaMm2)),
                        _CompareCell(
                            label: '本次需求',
                            size: formatSize(widget.demandWidthMm,
                                widget.demandLengthMm, unit),
                            area: formatArea(pieceArea)),
                        _CompareCell(
                            label: '切后余料',
                            size: formatSize(
                                remnant.widthMm, remnant.heightMm, unit),
                            area: formatArea(remnant.areaMm2)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '利用率 ${preview == null ? '—' : '${((preview.utilization ?? 0) * 100).toStringAsFixed(0)}%'} · 浪费 ${formatArea((preview?.wasteMm2 ?? 0) * widget.quantity)}',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.sub(context)),
                    ),
                    if (remnant.belowThreshold)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '余料最小边小于项目阈值（${widget.api.project.minUsableMm}mm），入库后可能不好再利用，仍可强制入库。',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.warning,
                                height: 1.45),
                          ),
                        ),
                      ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            BottomActionBar(
              hint: remnant == null
                  ? '整砖使用，扣减后剩 $remaining 片'
                  : '扣减后 ${_batch.code} 剩 $remaining 片',
              child: PrimaryButton(
                label: _submitting ? '提交中…' : '确认使用',
                loading: _submitting,
                onPressed: _submitted ? null : _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CutOptionCard extends StatelessWidget {
  const _CutOptionCard({
    required this.option,
    required this.batch,
    required this.selected,
    required this.onTap,
  });

  final CutOptionPreview? option;
  final Batch batch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool feasible = option?.feasible ?? false;
    final Color border = selected
        ? AppColors.accent(context)
        : (feasible ? AppColors.line(context) : AppColors.line(context));

    return InkWell(
      onTap: feasible ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: border, width: selected ? 2 : 1),
        ),
        child: Column(
          children: <Widget>[
            Opacity(
              opacity: feasible ? 1 : 0.35,
              child: option == null || !feasible
                  ? SizedBox(
                      height: 96,
                      child: Center(
                          child: Icon(Icons.block, color: AppColors.disabled)),
                    )
                  : TileShapePreview(
                      widthMm: batch.widthMm,
                      heightMm: batch.heightMm,
                      rects: batch.rects,
                      demand: option!.placement,
                      showCutLines: true,
                      remnantMode: true,
                      height: 96,
                      showDimensions: false,
                    ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(Icons.check_circle,
                      size: 16, color: AppColors.accent(context)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    option?.label ?? '—',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: feasible
                          ? AppColors.label(context)
                          : AppColors.disabled,
                    ),
                  ),
                ),
              ],
            ),
            if (!feasible)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('放不下',
                    style: TextStyle(fontSize: 11, color: AppColors.disabled)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemnantOptionCard extends StatelessWidget {
  const _RemnantOptionCard({
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    required this.remnant,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final Remnant remnant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
              color: selected ? color : AppColors.line(context),
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Opacity(
                    opacity: selected ? 1 : 0.55,
                    child: TileShapePreview(
                      widthMm: remnant.widthMm,
                      heightMm: remnant.heightMm,
                      rects: remnant.rects,
                      height: 72,
                      showDimensions: false,
                      remnantMode: true,
                    ),
                  ),
                  if (label == '丢弃')
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color:
                              AppColors.card(context).withValues(alpha: 0.85),
                          shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 22),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon,
                    size: 16, color: selected ? color : AppColors.sub(context)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? color : AppColors.label(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.sub(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareCell extends StatelessWidget {
  const _CompareCell(
      {required this.label, required this.size, required this.area});

  final String label;
  final String size;
  final String area;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.sub(context))),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(size, style: numberStyle(context, size: 14)),
            ),
            Text(area,
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.sub(context))),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: AppColors.sub(context))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
