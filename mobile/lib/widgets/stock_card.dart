import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import 'common.dart';

/// Inventory card: shape thumbnail → original size → current size → pieces.
class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.batch,
    required this.unit,
    this.onTap,
    this.onTrace,
    this.onConsume,
    this.onAdjust,
    this.highlight = false,
  });

  final Batch batch;
  final String unit;
  final VoidCallback? onTap;
  final VoidCallback? onTrace;

  /// 整砖批量使用（一次扣 N 片）
  final VoidCallback? onConsume;

  /// 手动调整片数（盘点纠错）
  final VoidCallback? onAdjust;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final Color accent = batch.isIrregular
        ? AppColors.warning
        : (batch.isLShape ? AppColors.remnant : AppColors.primary);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              highlight ? AppColors.accent(context) : AppColors.line(context),
          width: highlight ? 1.8 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.page(context),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: AppColors.line(context)),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: TileThumb(batch: batch),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                batch.code,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.sub(context),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (batch.isIrregular)
                                Tag(
                                    label: '异形',
                                    color: accent,
                                    icon: Icons.dashboard_customize_outlined)
                              else if (batch.isLShape)
                                Tag(
                                    label: 'L 形',
                                    color: accent,
                                    icon: Icons.change_history)
                              else
                                Tag(label: '矩形', color: accent),
                              const SizedBox(width: 4),
                              Tag(
                                label:
                                    batch.sourceType == 'cut' ? '切割余料' : '原始录入',
                                // 来源也用颜色区分：原始录入蓝、切割余料绿
                                color: batch.sourceType == 'cut'
                                    ? AppColors.success
                                    : AppColors.primary,
                                icon: batch.sourceType == 'cut'
                                    ? Icons.content_cut
                                    : Icons.add_box_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatSize(batch.widthMm, batch.heightMm, unit),
                            style: numberStyle(context, size: 19),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '面积 ${formatArea(batch.areaMm2)} · ${formatRelative(batch.createdAt)}',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.sub(context)),
                          ),
                          if (batch.location.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.place_outlined,
                                      size: 14, color: AppColors.sub(context)),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      batch.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.sub(context)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text('${batch.quantity}',
                            style: numberStyle(context, size: 28)),
                        Text('片',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.sub(context))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    if (batch.belowMinUsable)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Tag(
                            label: '低于最小可用尺寸',
                            color: AppColors.warning,
                            icon: Icons.warning_amber_rounded),
                      ),
                    const Spacer(),
                    if (onAdjust != null)
                      _ActionChip(
                        icon: Icons.tune,
                        label: '调整',
                        color: AppColors.warning,
                        onTap: onAdjust,
                      ),
                    if (onConsume != null) ...<Widget>[
                      const SizedBox(width: 6),
                      _ActionChip(
                        icon: Icons.remove_circle_outline,
                        label: '用掉',
                        color: AppColors.primary,
                        onTap: onConsume,
                      ),
                    ],
                    const SizedBox(width: 6),
                    _ActionChip(
                      icon: Icons.account_tree_outlined,
                      label: '溯源',
                      color: AppColors.success,
                      onTap: onTrace,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片底部的小操作按钮：图标 + 文字 + 浅底，用颜色区分用途。
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, label free shape drawing used inside cards.
class TileThumb extends StatelessWidget {
  const TileThumb({super.key, required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return CustomPaint(
          painter: _ThumbPainter(batch: batch, dark: AppColors.isDark(context)),
          size: constraints.biggest,
        );
      },
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({required this.batch, required this.dark});

  final Batch batch;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (batch.widthMm <= 0 || batch.heightMm <= 0) return;
    final double scale =
        (size.width - 8) / batch.widthMm < (size.height - 8) / batch.heightMm
            ? (size.width - 8) / batch.widthMm
            : (size.height - 8) / batch.heightMm;
    final double w = batch.widthMm * scale;
    final double h = batch.heightMm * scale;
    final double ox = (size.width - w) / 2;
    final double oy = (size.height - h) / 2;

    final Paint fill = Paint()
      ..color = batch.isIrregular
          // 异形用橙黄（对应 AppColors.warning），和标签颜色一致
          ? (dark ? const Color(0xFF5A3A1A) : const Color(0xFFFBE3CE))
          : batch.isLShape
              ? (dark ? const Color(0xFF4A3560) : const Color(0xFFEDE4F5))
              : (dark ? const Color(0xFF2F3740) : const Color(0xFFE8EDF3));
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = dark ? const Color(0xFF5A6672) : const Color(0xFFB7C2CF);

    final List<ShapeRect> rects = batch.rects.isEmpty
        ? <ShapeRect>[
            ShapeRect(x: 0, y: 0, w: batch.widthMm, h: batch.heightMm)
          ]
        : batch.rects;

    final Rect bbox = Rect.fromLTWH(ox, oy, w, h);
    canvas.drawRect(
        bbox, Paint()..color = dark ? const Color(0xFF1E1E1E) : Colors.white);

    for (final ShapeRect r in rects) {
      final Rect rect = Rect.fromLTWH(
        ox + r.x * scale,
        oy + (batch.heightMm - r.y - r.h) * scale,
        r.w * scale,
        r.h * scale,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
    }
    canvas.drawRect(bbox, border);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) =>
      old.batch.id != batch.id ||
      old.batch.quantity != batch.quantity ||
      old.batch.widthMm != batch.widthMm ||
      old.dark != dark;
}
