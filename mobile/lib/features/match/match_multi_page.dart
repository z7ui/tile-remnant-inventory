import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/nesting_preview.dart';

/// 多尺寸一起匹配：大件优先，一块砖内递归切割（一刀切到底）。
class MatchMultiPage extends StatefulWidget {
  const MatchMultiPage({super.key, required this.api, required this.onChanged});

  final ProjectApi api;
  final VoidCallback onChanged;

  @override
  State<MatchMultiPage> createState() => _MatchMultiPageState();
}

class _DemandRow {
  _DemandRow({String length = '', String width = '', String quantity = '1'})
      : length = TextEditingController(text: length),
        width = TextEditingController(text: width),
        quantity = TextEditingController(text: quantity);

  final TextEditingController length;
  final TextEditingController width;
  final TextEditingController quantity;

  void dispose() {
    length.dispose();
    width.dispose();
    quantity.dispose();
  }
}

class _MatchMultiPageState extends State<MatchMultiPage> {
  final List<_DemandRow> _rows = <_DemandRow>[_DemandRow()];
  String _unit = 'mm';
  bool _prefsLoaded = false;
  bool _loading = false;
  String? _error;
  MultiMatchResult? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final Session session = SessionScope.of(context);
    _unit = session.prefs.unitFor(
        widget.api.project.id, widget.api.project.defaultUnit);
  }

  @override
  void dispose() {
    for (final _DemandRow row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    if (_rows.length >= 20) {
      showSnack(context, '最多 20 行，再多建议分批匹配', error: true);
      return;
    }
    setState(() => _rows.add(_DemandRow()));
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      if (_rows.isEmpty) _rows.add(_DemandRow());
    });
  }

  Future<void> _run() async {
    final List<Map<String, dynamic>> demands = <Map<String, dynamic>>[];
    for (int i = 0; i < _rows.length; i++) {
      final _DemandRow row = _rows[i];
      final String? lengthError = validateLength(row.length.text, _unit);
      final String? widthError = validateLength(row.width.text, _unit);
      if (lengthError != null || widthError != null) {
        setState(() => _error = '第 ${i + 1} 行：${lengthError ?? widthError}');
        return;
      }
      final int quantity = int.tryParse(row.quantity.text) ?? 0;
      if (quantity < 1) {
        setState(() => _error = '第 ${i + 1} 行：数量至少 1 片');
        return;
      }
      demands.add(<String, dynamic>{
        'length': row.length.text,
        'width': row.width.text,
        'quantity': quantity,
      });
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MultiMatchResult result =
          await widget.api.matchMulti(demands: demands, unit: _unit);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final MultiMatchResult? result = _result;
    return Scaffold(
      appBar: buildAppBar(context, '多尺寸匹配'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
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
                const SectionTitle(
                    title: '要切哪些尺寸',
                    subtitle: '大件优先；一块砖里可以同时切出多个尺寸'),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Text('单位',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.sub(context))),
                    const SizedBox(width: AppSpacing.sm),
                    for (final String unit in <String>['mm', 'cm'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(unit),
                          selected: _unit == unit,
                          onSelected: (_) => setState(() => _unit = unit),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ...List<Widget>.generate(
                    _rows.length, (int index) => _rowWidget(index)),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('再加一行（${_rows.length}/20）'),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: '开始匹配',
                  icon: Icons.grid_view_rounded,
                  loading: _loading,
                  onPressed: _run,
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!, onRetry: _run),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!_loading && result != null) _buildResult(result),
        ],
      ),
    );
  }

  Widget _rowWidget(int index) {
    final _DemandRow row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: row.length,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '长',
                suffixText: _unit,
                isDense: true,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('×'),
          ),
          Expanded(
            child: TextField(
              controller: row.width,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '宽',
                suffixText: _unit,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextField(
              controller: row.quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '数量',
                suffixText: '片',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _removeRow(index),
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除这一行',
          ),
        ],
      ),
    );
  }

  Widget _buildResult(MultiMatchResult result) {
    final MultiMatchSummary summary = result.summary;
    final bool shortage = summary.missingPieces > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            '预览：还没有扣库存。确认使用（一次扣多块 + 余料入库）下一步开放。',
            style: TextStyle(
                fontSize: 12, height: 1.5, color: AppColors.sub(context)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: (shortage ? AppColors.warning : AppColors.success)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
                color: (shortage ? AppColors.warning : AppColors.success)
                    .withValues(alpha: 0.32)),
          ),
          child: Text(
            shortage
                ? '用 ${summary.blocksUsed} 块砖，满足 ${summary.fulfilledPieces}/${summary.demandPieces} 片，还差 ${summary.missingPieces} 片'
                : '用 ${summary.blocksUsed} 块砖，满足全部 ${summary.demandPieces} 片，利用率 ${(summary.utilization * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: shortage ? AppColors.warning : AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...result.blocks.map(_blockCard),
        if (result.skipped.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '未参与混排：${result.skipped.join('，')}',
            style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
          ),
        ],
      ],
    );
  }

  Widget _blockCard(NestingBlock block) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
              Text('#${block.batchNo.toString().padLeft(4, '0')}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${block.widthMm}×${block.heightMm}',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.sub(context))),
              const Spacer(),
              Text(
                  '${block.totalPieces} 片 · ${(block.utilization * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.sub(context))),
            ],
          ),
          const SizedBox(height: 8),
          if (block.cuttings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                height: 150,
                child: NestingPreview(
                  widthMm: block.widthMm,
                  heightMm: block.heightMm,
                  cuttings: block.cuttings,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: block.pieces
                .map((NestingPiece piece) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${piece.widthMm}×${piece.heightMm} × ${piece.quantity}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
