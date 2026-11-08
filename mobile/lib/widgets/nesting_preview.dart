import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/models.dart';

/// 一块砖的混排图：外框 = 原砖，色块 = 每一片（不同尺寸不同颜色）。
class NestingPreview extends StatelessWidget {
  const NestingPreview({
    super.key,
    required this.widthMm,
    required this.heightMm,
    required this.cuttings,
  });

  final int widthMm;
  final int heightMm;
  final List<ShapeRect> cuttings;

  @override
  Widget build(BuildContext context) {
    if (widthMm <= 0 || heightMm <= 0) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: widthMm / heightMm,
      child: CustomPaint(
        painter: _NestingPainter(
          widthMm: widthMm,
          heightMm: heightMm,
          cuttings: cuttings,
          dark: AppColors.isDark(context),
        ),
      ),
    );
  }
}

class _NestingPainter extends CustomPainter {
  _NestingPainter({
    required this.widthMm,
    required this.heightMm,
    required this.cuttings,
    required this.dark,
  });

  final int widthMm;
  final int heightMm;
  final List<ShapeRect> cuttings;
  final bool dark;

  static const List<Color> _lightColors = <Color>[
    Color(0xFFBFD7F2),
    Color(0xFFBFE3CC),
    Color(0xFFF7DFB5),
    Color(0xFFE8C9E0),
    Color(0xFFD9D6CB),
  ];
  static const List<Color> _darkColors = <Color>[
    Color(0xFF2C4A6B),
    Color(0xFF2A4A3A),
    Color(0xFF5A4526),
    Color(0xFF4A2E42),
    Color(0xFF3A3A36),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double scale =
        (size.width - 8) / widthMm < (size.height - 8) / heightMm
            ? (size.width - 8) / widthMm
            : (size.height - 8) / heightMm;
    final double w = widthMm * scale;
    final double h = heightMm * scale;
    final double ox = (size.width - w) / 2;
    final double oy = (size.height - h) / 2;

    canvas.drawRect(
      Rect.fromLTWH(ox, oy, w, h),
      Paint()..color = dark ? const Color(0xFF1E1E1E) : Colors.white,
    );

    final List<int> areas =
        cuttings.map((ShapeRect r) => r.area).toSet().toList()..sort();
    final List<Color> palette = dark ? _darkColors : _lightColors;
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = dark ? const Color(0xFF5A6672) : const Color(0xFF8C98A6);

    for (final ShapeRect r in cuttings) {
      final int idx = areas.indexOf(r.area);
      final Rect rect = Rect.fromLTWH(
        ox + r.x * scale,
        oy + r.y * scale,
        r.w * scale,
        r.h * scale,
      );
      canvas.drawRect(rect, Paint()..color = palette[idx % palette.length]);
      canvas.drawRect(rect, border);
    }

    canvas.drawRect(
      Rect.fromLTWH(ox, oy, w, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = dark ? const Color(0xFF7A8794) : const Color(0xFF5F6C78),
    );
  }

  @override
  bool shouldRepaint(covariant _NestingPainter old) =>
      old.widthMm != widthMm ||
      old.heightMm != heightMm ||
      old.cuttings.length != cuttings.length ||
      old.dark != dark;
}
