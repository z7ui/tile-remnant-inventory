import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/models.dart';

/// Palette for the俯视图 (top view) drawings.
class ShapePalette {
  const ShapePalette({
    required this.stock,
    required this.stockBorder,
    required this.demand,
    required this.demandBorder,
    required this.remnant,
    required this.hatch,
    required this.cut,
    required this.label,
  });

  final Color stock;
  final Color stockBorder;
  final Color demand;
  final Color demandBorder;
  final Color remnant;
  final Color hatch;
  final Color cut;
  final Color label;

  static ShapePalette of(BuildContext context) {
    final bool dark = AppColors.isDark(context);
    return ShapePalette(
      stock: dark ? const Color(0xFF2A3138) : const Color(0xFFE8EDF3),
      stockBorder: dark ? const Color(0xFF4A5560) : const Color(0xFFB7C2CF),
      demand: (dark ? AppColors.primaryDark : AppColors.primary).withValues(alpha: 0.85),
      demandBorder: dark ? AppColors.primaryDark : AppColors.primary,
      remnant: (dark ? const Color(0xFFB39DDB) : AppColors.remnant).withValues(alpha: 0.35),
      hatch: dark ? const Color(0xFF6A1B9A).withValues(alpha: 0.45) : AppColors.remnant.withValues(alpha: 0.32),
      cut: dark ? const Color(0xFFFFB74D) : AppColors.warning,
      label: dark ? AppColors.textDark : AppColors.textSecondary,
    );
  }
}

/// Reusable top-view preview of a tile: outer rectangle, L notch, demand block
/// and the leftover. Uses real proportions — never stretches.
class TileShapePreview extends StatelessWidget {
  const TileShapePreview({
    super.key,
    required this.widthMm,
    required this.heightMm,
    this.rects = const <ShapeRect>[],
    this.demand,
    this.demandCount = 1,
    this.demandAlongY = false,
    this.remnantMode = false,
    this.showCutLines = false,
    this.height = 160,
    this.showLegend = false,
    this.showDimensions = true,
    this.caption,
  });

  final int widthMm;
  final int heightMm;
  final List<ShapeRect> rects;
  final ShapeRect? demand;
  final int demandCount;
  final bool demandAlongY;
  final bool remnantMode;
  final bool showCutLines;
  final double height;
  final bool showLegend;
  final bool showDimensions;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ShapePalette palette = ShapePalette.of(context);
    final List<ShapeRect> region = rects.isEmpty && widthMm > 0 && heightMm > 0
        ? <ShapeRect>[ShapeRect(x: 0, y: 0, w: widthMm, h: heightMm)]
        : rects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RepaintBoundary(
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _TileShapePainter(
                widthMm: widthMm,
                heightMm: heightMm,
                rects: region,
                demand: demand,
                demandCount: demandCount,
                demandAlongY: demandAlongY,
                remnantMode: remnantMode,
                showCutLines: showCutLines,
                showDimensions: showDimensions,
                palette: palette,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        if (showLegend) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _LegendDot(color: palette.stock, label: '原砖'),
              if (demand != null)
                _LegendDot(
                    color: palette.demand,
                    label: demandCount > 1 ? '本次需求 × $demandCount' : '本次需求'),
              if (remnantMode || showCutLines) _LegendDot(color: palette.remnant, label: '切后余料'),
              if (remnantMode) _LegendDot(color: palette.hatch, label: '缺口/不可用'),
            ],
          ),
        ],
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption!,
            style: TextStyle(fontSize: 12, color: AppColors.sub(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.line(context)),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.sub(context))),
      ],
    );
  }
}

class _TileShapePainter extends CustomPainter {
  _TileShapePainter({
    required this.widthMm,
    required this.heightMm,
    required this.rects,
    required this.demand,
    required this.demandCount,
    required this.demandAlongY,
    required this.remnantMode,
    required this.showCutLines,
    required this.showDimensions,
    required this.palette,
  });

  final int widthMm;
  final int heightMm;
  final List<ShapeRect> rects;
  final ShapeRect? demand;
  final int demandCount;
  final bool demandAlongY;
  final bool remnantMode;
  final bool showCutLines;
  final bool showDimensions;
  final ShapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (widthMm <= 0 || heightMm <= 0 || size.width <= 8 || size.height <= 8) return;

    const double pad = 26;
    final double scale = math.min(
      (size.width - pad * 2) / widthMm,
      (size.height - pad * 2) / heightMm,
    );
    if (scale <= 0) return;

    final double drawW = widthMm * scale;
    final double drawH = heightMm * scale;
    final double ox = (size.width - drawW) / 2;
    final double oy = (size.height - drawH) / 2;

    Rect rectOf(ShapeRect r) => Rect.fromLTWH(
          ox + r.x * scale,
          oy + (heightMm - r.y - r.h) * scale,
          r.w * scale,
          r.h * scale,
        );

    final Rect bbox = Rect.fromLTWH(ox, oy, drawW, drawH);
    final int regionArea = rects.fold<int>(0, (int sum, ShapeRect r) => sum + r.area);
    final bool hasNotch = regionArea < widthMm * heightMm - 1;

    // 1. hatched bbox so the notch / missing area is visually obvious
    if (hasNotch) {
      canvas.save();
      canvas.clipRect(bbox);
      final Paint hatch = Paint()
        ..color = palette.hatch
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      const double step = 9;
      for (double d = -drawH; d < drawW + drawH; d += step) {
        canvas.drawLine(Offset(ox + d, oy), Offset(ox + d - drawH, oy + drawH), hatch);
      }
      canvas.restore();
    }

    // 2. the usable region
    final Paint fill = Paint()..color = demand != null && remnantMode ? palette.remnant : palette.stock;
    final Paint border = Paint()
      ..color = palette.stockBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final ShapeRect r in rects) {
      final Rect rect = rectOf(r);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
    }

    // 3. outer boundary
    canvas.drawRect(
      bbox,
      Paint()
        ..color = palette.stockBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // 4. demand block + cut lines
    final ShapeRect? d = demand;
    if (d != null) {
      final int n = demandCount <= 0 ? 1 : demandCount;
      for (int i = 0; i < n; i++) {
        // 多片需求沿切割方向平移：long_side_cut 沿长边(y)堆叠，short_side_cut 沿短边(x)排开
        final ShapeRect piece = ShapeRect(
          x: d.x + (demandAlongY ? 0 : i * d.w),
          y: d.y + (demandAlongY ? i * d.h : 0),
          w: d.w,
          h: d.h,
        );
        final Rect rect = rectOf(piece);
        canvas.drawRect(rect, Paint()..color = palette.demand);
        canvas.drawRect(
          rect,
          Paint()
            ..color = palette.demandBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        if (showCutLines) {
          if (n == 1) {
            // 单片：沿需求块右边、上边画两条切缝
            _dashedLine(canvas, Offset(rect.right, bbox.top), Offset(rect.right, bbox.bottom));
            _dashedLine(canvas, Offset(bbox.left, rect.top), Offset(bbox.right, rect.top));
          } else if (i < n - 1) {
            // 多片：片与片之间画分界线
            if (demandAlongY) {
              _dashedLine(canvas, Offset(bbox.left, rect.bottom), Offset(bbox.right, rect.bottom));
            } else {
              _dashedLine(canvas, Offset(rect.right, bbox.top), Offset(rect.right, bbox.bottom));
            }
          }
        }
        if (rect.width > 46 && rect.height > 22) {
          _text(canvas, n > 1 ? '${i + 1}' : '需求', rect.center, Colors.white, 11, bold: true);
        }
      }
    }

    // 5. dimensions
    if (showDimensions) {
      _text(canvas, '$widthMm', Offset(bbox.center.dx, bbox.bottom + 13), palette.label, 11);
      _text(canvas, '$heightMm', Offset(bbox.left - 14, bbox.center.dy), palette.label, 11);
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to) {
    final Paint paint = Paint()
      ..color = palette.cut
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const double dash = 6;
    const double gap = 5;
    final double distance = (to - from).distance;
    if (distance <= 0) return;
    final Offset unit = (to - from) / distance;
    double travelled = 0;
    while (travelled < distance) {
      final double end = math.min(travelled + dash, distance);
      canvas.drawLine(from + unit * travelled, from + unit * end, paint);
      travelled = end + gap;
    }
  }

  void _text(Canvas canvas, String text, Offset center, Color color, double size, {bool bold = false}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TileShapePainter old) {
    return old.widthMm != widthMm ||
        old.heightMm != heightMm ||
        old.demand != demand ||
        old.demandCount != demandCount ||
        old.demandAlongY != demandAlongY ||
        old.remnantMode != remnantMode ||
        old.showCutLines != showCutLines ||
        old.rects != rects ||
        old.palette.demand != palette.demand;
  }
}
