import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../widgets/common.dart';
import '../../widgets/tile_shape_preview.dart';
import '../trace/trace_page.dart';

class MovementDetailPage extends StatelessWidget {
  const MovementDetailPage({super.key, required this.api, required this.movement});

  final ProjectApi api;
  final Movement movement;

  Color _color() {
    switch (movement.type) {
      case 'usage':
        return AppColors.primary;
      case 'cut_remnant':
        return AppColors.remnant;
      case 'remnant_discard':
      case 'void':
        return AppColors.danger;
      case 'adjust':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  ShapeRect? _demandRect() {
    final int? usedLong = movement.usedLengthMm;
    final int? usedShort = movement.usedWidthMm;
    final int? stockW = movement.widthBeforeMm;
    final int? stockH = movement.heightBeforeMm;
    if (usedLong == null || usedShort == null || stockW == null || stockH == null) return null;
    final int shortEdge = stockW <= stockH ? stockW : stockH;
    final int longEdge = stockW <= stockH ? stockH : stockW;
    if (usedShort <= shortEdge && usedLong <= longEdge) {
      return ShapeRect(x: 0, y: 0, w: usedShort, h: usedLong);
    }
    if (usedLong <= shortEdge && usedShort <= longEdge) {
      return ShapeRect(x: 0, y: 0, w: usedLong, h: usedShort);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color();
    final ShapeRect? demand = _demandRect();
    final int? stockW = movement.widthBeforeMm;
    final int? stockH = movement.heightBeforeMm;

    return Scaffold(
      appBar: buildAppBar(context, '流水详情'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: color.withOpacity(0.28)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.receipt_long, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(movement.typeLabel, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(height: 2),
                      Text(
                        '${movement.batchCode} · ${formatDateTime(movement.createdAt)}',
                        style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
                      ),
                    ],
                  ),
                ),
                Text(
                  movement.quantityDelta == 0
                      ? '${movement.quantityAfter} 片'
                      : '${movement.quantityBefore} → ${movement.quantityAfter} 片',
                  style: numberStyle(context, size: 15),
                ),
              ],
            ),
          ),
          if (demand != null && stockW != null && stockH != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle(title: '切割示意', subtitle: '按流水记录还原，位置为示意'),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.line(context)),
              ),
              child: TileShapePreview(
                widthMm: stockW,
                heightMm: stockH,
                demand: demand,
                remnantMode: true,
                showCutLines: true,
                height: 190,
                showLegend: true,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle(title: '变动明细'),
          _row(context, '批次', movement.batchCode),
          _row(context, '变动前片数', '${movement.quantityBefore}'),
          _row(context, '变动后片数', '${movement.quantityAfter}'),
          _row(
            context,
            '变动前尺寸',
            movement.widthBeforeMm == null ? '—' : '${movement.widthBeforeMm}×${movement.heightBeforeMm}mm',
          ),
          _row(
            context,
            '变动后尺寸',
            movement.widthAfterMm == null ? '—' : '${movement.widthAfterMm}×${movement.heightAfterMm}mm',
          ),
          _row(
            context,
            '使用尺寸',
            movement.usedLengthMm == null ? '—' : '${movement.usedLengthMm}×${movement.usedWidthMm}mm',
          ),
          _row(context, '切割方式', movement.cutOptionLabel ?? '—'),
          _row(context, '余料处置', movement.remnantActionLabel ?? '—'),
          _row(
            context,
            '余料形状',
            movement.remnantShape == null
                ? '—'
                : '${movement.remnantShape == 'l_shape' ? 'L 形' : '矩形'} · ${formatArea(movement.remnantAreaMm2 ?? 0)}',
          ),
          _row(context, '操作设备', movement.deviceId.isEmpty ? '—' : movement.deviceId),
          _row(context, '关联使用记录', movement.usageRecordId ?? '—'),
          _row(context, '备注', movement.note.isEmpty ? '—' : movement.note),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: AppSizes.primaryButton,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TracePage(api: api, batchId: movement.batchId, title: movement.batchCode),
                ),
              ),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('打开溯源对比'),
            ),
          ),
        ],
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
            width: 96,
            child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.sub(context))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
