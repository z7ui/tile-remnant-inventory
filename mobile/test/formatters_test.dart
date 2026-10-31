import 'package:flutter_test/flutter_test.dart';
import 'package:tile_remnant/core/formatters.dart';

void main() {
  group('parseLengthToMm', () {
    test('plain numbers use the project unit', () {
      expect(parseLengthToMm('800', 'mm'), 800);
      expect(parseLengthToMm('80', 'cm'), 800);
    });

    test('suffix wins over the unit selector', () {
      expect(parseLengthToMm('80cm', 'mm'), 800);
      expect(parseLengthToMm('800mm', 'cm'), 800);
      expect(parseLengthToMm('1.2m', 'mm'), 1200);
    });

    test('decimals and spaces', () {
      expect(parseLengthToMm(' 80.5 cm ', 'mm'), 805);
      expect(parseLengthToMm('0.1cm', 'mm'), 1);
    });

    test('rejects garbage', () {
      expect(parseLengthToMm('', 'mm'), isNull);
      expect(parseLengthToMm('abc', 'mm'), isNull);
      expect(parseLengthToMm('0', 'mm'), isNull);
      expect(parseLengthToMm('-5', 'mm'), isNull);
      expect(parseLengthToMm('8 0', 'mm'), isNull);
    });
  });

  group('formatting', () {
    test('formatMm strips trailing zeros', () {
      expect(formatMm(800, 'cm'), '80cm');
      expect(formatMm(805, 'cm'), '80.5cm');
      expect(formatMm(800, 'mm'), '800mm');
    });

    test('formatSize always puts the short edge first', () {
      expect(formatSize(900, 800, 'mm'), '800 × 900 mm');
      expect(formatSize(900, 800, 'cm'), '80 × 90cm');
    });

    test('formatArea switches between dm2 and m2', () {
      expect(formatArea(720000), '0.72 m²');
      expect(formatArea(5000), '0.50 dm²');
    });

    test('newIdempotencyKey is long enough for the API', () {
      final String key = newIdempotencyKey();
      expect(key.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(key), isTrue);
      expect(key, isNot(newIdempotencyKey()));
    });
  });
}
