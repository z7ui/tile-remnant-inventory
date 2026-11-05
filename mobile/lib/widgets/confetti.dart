import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 全屏礼炮：彩色纸片从上方炸开、受重力飘落，约 3.2 秒后自动移除。
///
/// 用法：`ConfettiBurst.show(context)`。整层 [IgnorePointer]，不挡用户操作。
class ConfettiBurst {
  ConfettiBurst._();

  static void show(BuildContext context, {int pieces = 140}) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ConfettiLayer(
        pieces: pieces,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _ConfettiLayer extends StatefulWidget {
  const _ConfettiLayer({required this.pieces, required this.onDone});

  final int pieces;
  final VoidCallback onDone;

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<_ConfettiLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  static const List<Color> _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    final math.Random rnd = math.Random();
    _pieces = List<_Piece>.generate(widget.pieces, (int i) {
      final double angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 1.7;
      final double speed = 240 + rnd.nextDouble() * 360;
      return _Piece(
        originX: rnd.nextDouble(),
        originY: 0.06 + rnd.nextDouble() * 0.14,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        size: 6 + rnd.nextDouble() * 9,
        color: _palette[i % _palette.length],
        spin: (rnd.nextDouble() - 0.5) * 9,
        phase: rnd.nextDouble() * math.pi * 2,
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) widget.onDone();
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _ConfettiPainter(pieces: _pieces, t: _controller.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.originX,
    required this.originY,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
  });

  final double originX;
  final double originY;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double spin;
  final double phase;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.t});

  final List<_Piece> pieces;

  /// 0 → 1
  final double t;

  /// 动画总时长（秒），和 [AnimationController] 保持一致。
  static const double _durationSec = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final double seconds = t * _durationSec;
    final double gravity = size.height * 1.5;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final double fade = (1 - t * 0.9).clamp(0.0, 1.0);

    for (final _Piece p in pieces) {
      // 横向：初速度 + 简单的空气减速（0.4 系数）
      final double x = p.originX * size.width + p.vx * seconds * 0.4;
      // 纵向：初速度 + 重力
      final double y = p.originY * size.height +
          p.vy * seconds +
          0.5 * gravity * seconds * seconds;
      if (y > size.height + 60 || y < -80) continue;

      paint.color = p.color.withValues(alpha: fade * 0.95);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * seconds + p.phase);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 1.7,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
