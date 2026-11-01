import 'dart:math' as math;

/// Parses user input like `800`, `80cm`, `800mm`, `80.5cm` into millimetres.
/// Returns `null` when the text is not a valid positive length.
int? parseLengthToMm(String raw, String unit) {
  // 只去掉首尾空白，不吞中间的空格：`8 0` 是手滑，不该被当成 80。
  // 数字与单位之间的空格由正则里的 \s* 允许（`80.5 cm`）。
  final String text = raw.trim().replaceAll('，', '.');
  if (text.isEmpty) return null;
  final RegExpMatch? match = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(mm|cm|m)?$', caseSensitive: false).firstMatch(text);
  if (match == null) return null;

  final double value = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 0;
  if (value <= 0) return null;

  final String? suffix = match.group(2)?.toLowerCase();
  final double factor = switch (suffix ?? unit) {
    'cm' => 10,
    'm' => 1000,
    _ => 1,
  };
  final int mm = (value * factor).round();
  if (mm <= 0 || mm > 100000) return null;
  return mm;
}

/// Validation message for a dimension field, or `null` when valid.
String? validateLength(String raw, String unit) {
  if (raw.trim().isEmpty) return '请输入尺寸';
  if (parseLengthToMm(raw, unit) == null) {
    return '尺寸需为数字，例如 800 或 80.5';
  }
  return null;
}

String _trimZero(String value) {
  if (!value.contains('.')) return value;
  return value.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 800 -> `80cm` (unit=cm) / `800mm` (unit=mm).
String formatMm(int mm, String unit) {
  if (unit == 'cm') {
    final String text = (mm / 10).toStringAsFixed(1);
    return '${_trimZero(text)}cm';
  }
  return '${mm}mm';
}

int _short(int a, int b) => math.min(a, b);
int _long(int a, int b) => math.max(a, b);

/// `80 × 90cm` — always short edge first so cards stay comparable.
String formatSize(int widthMm, int heightMm, String unit) {
  final int s = _short(widthMm, heightMm);
  final int l = _long(widthMm, heightMm);
  if (unit == 'cm') {
    return '${_trimZero((s / 10).toStringAsFixed(1))} × ${_trimZero((l / 10).toStringAsFixed(1))}cm';
  }
  return '$s × $l mm';
}

String formatArea(int areaMm2) {
  // 阈值取半平方米：工地口径里 0.72 m² 就该念「0.72 平米」，
  // 换算成 72 dm² 反而要在脑子里再除一次。只有真小的边角料（< 0.5 m²）才用 dm²。
  final double m2 = areaMm2 / 1000000;
  if (m2 >= 0.5) return '${m2.toStringAsFixed(2)} m²';
  return '${(areaMm2 / 10000).toStringAsFixed(2)} dm²';
}

DateTime? _parseIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatDateTime(String? iso) {
  final DateTime? dt = _parseIso(iso);
  if (dt == null) return '—';
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
}

String formatTime(String? iso) {
  final DateTime? dt = _parseIso(iso);
  if (dt == null) return '—';
  return '${_two(dt.hour)}:${_two(dt.minute)}';
}

String formatDateHeader(String? iso) {
  final DateTime? dt = _parseIso(iso);
  if (dt == null) return '—';
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(dt.year, dt.month, dt.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
}

String formatRelative(String? iso) {
  final DateTime? dt = _parseIso(iso);
  if (dt == null) return '暂无记录';
  final Duration diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
}

/// Short idempotency key — 32 hex chars, generated without extra dependencies.
String newIdempotencyKey() {
  final math.Random random = math.Random.secure();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
