import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tile_remnant/core/invite.dart';
import 'package:tile_remnant/core/models.dart';
import 'package:tile_remnant/widgets/tile_shape_preview.dart';

void main() {
  group('parseInvitePayload', () {
    test('custom scheme with server', () {
      final InvitePayload? payload = parseInvitePayload(
        'tileremnant://join?server=https%3A%2F%2Ftiles.example.com&code=abcd2345ef',
      );
      expect(payload, isNotNull);
      expect(payload!.code, 'ABCD2345EF');
      expect(payload.server, 'https://tiles.example.com');
    });

    test('printed https link', () {
      final InvitePayload? payload = parseInvitePayload('https://tiles.example.com/join?code=XYZ789');
      expect(payload?.code, 'XYZ789');
      expect(payload?.server, 'https://tiles.example.com');
    });

    test('bare code', () {
      expect(parseInvitePayload('ABCD2345EF')?.code, 'ABCD2345EF');
    });

    test('rejects unrelated text', () {
      expect(parseInvitePayload('hello world'), isNull);
      expect(parseInvitePayload(''), isNull);
    });
  });

  group('TileShapePreview', () {
    testWidgets('renders an L shaped remnant with a legend', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 260,
              child: TileShapePreview(
                widthMm: 800,
                heightMm: 900,
                rects: const <ShapeRect>[
                  ShapeRect(x: 0, y: 0, w: 800, h: 600),
                  ShapeRect(x: 0, y: 600, w: 600, h: 300),
                ],
                demand: const ShapeRect(x: 0, y: 0, w: 500, h: 600),
                remnantMode: true,
                showCutLines: true,
                showLegend: true,
                height: 180,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('本次需求'), findsOneWidget);
      expect(find.text('切后余料'), findsOneWidget);
    });
  });

  group('Batch parsing', () {
    test('exposes normalised edges and L flag', () {
      final Batch batch = Batch.fromJson(<String, dynamic>{
        'id': 'abc',
        'batch_no': 7,
        'shape_type': 'l_shape',
        'width_mm': 800,
        'height_mm': 900,
        'area_mm2': 660000,
        'quantity': 2,
        'initial_quantity': 3,
        'status': 'available',
        'source_type': 'cut',
        'location': '阳台',
        'created_at': '2026-10-31T12:00:00Z',
        'rects': <Map<String, dynamic>>[
          <String, dynamic>{'x': 0, 'y': 0, 'w': 800, 'h': 600},
          <String, dynamic>{'x': 0, 'y': 600, 'w': 600, 'h': 300},
        ],
        'notch': <String, dynamic>{'w': 200, 'h': 300, 'corner': 'top_right'},
      });
      expect(batch.isLShape, isTrue);
      expect(batch.shortMm, 800);
      expect(batch.longMm, 900);
      expect(batch.rects, hasLength(2));
      expect(batch.notch?.label, '右上缺口');
      expect(batch.code, '#0007');
    });
  });
}
