import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_application_1/widgets/dynamic_contrast_text.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ByteData> _capture(WidgetTester tester, Key key) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final ByteData? data = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage();
    return image.toByteData();
  });
  return data!;
}

/// Max/min luminance (0-255) over an opaque-pixel rect of an RGBA capture.
(int, int) _lumRange(ByteData rgba, int imageWidth, Rect rect) {
  int maxLum = 0;
  int minLum = 255;
  for (int y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (int x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final int i = (y * imageWidth + x) * 4;
      final int lum = (rgba.getUint8(i) +
              rgba.getUint8(i + 1) +
              rgba.getUint8(i + 2)) ~/
          3;
      if (lum > maxLum) maxLum = lum;
      if (lum < minLum) minLum = lum;
    }
  }
  return (maxLum, minLum);
}

void main() {
  testWidgets('text inverts per-pixel across a black/white boundary',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const ValueKey<String> probeKey = ValueKey<String>('probe');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: probeKey,
          child: Stack(
            fit: StackFit.expand,
            children: const [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: Colors.black)),
                  Expanded(child: ColoredBox(color: Colors.white)),
                ],
              ),
              Center(
                child: DynamicContrastText(
                  'WWWWWWWWWW',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final ByteData rgba = await _capture(tester, probeKey);

    // Backgrounds themselves must be intact outside the text row.
    final (int, int) leftBg = _lumRange(rgba, 390, const Rect.fromLTRB(10, 10, 60, 40));
    final (int, int) rightBg = _lumRange(rgba, 390, const Rect.fromLTRB(330, 10, 380, 40));
    expect(leftBg.$1, 0, reason: 'left band should be pure black');
    expect(rightBg.$2, 255, reason: 'right band should be pure white');

    // The glyph row spans the split. Over black, glyphs must invert to
    // near-white; over white, the SAME string must invert to near-black.
    const Rect textRowLeft = Rect.fromLTRB(20, 85, 185, 115);
    const Rect textRowRight = Rect.fromLTRB(205, 85, 370, 115);
    final (int, int) left = _lumRange(rgba, 390, textRowLeft);
    final (int, int) right = _lumRange(rgba, 390, textRowRight);
    expect(left.$1, greaterThan(240),
        reason: 'glyphs over the black half must render near-white');
    expect(right.$2, lessThan(15),
        reason: 'glyphs over the white half must render near-black');
  });

  testWidgets('blend is an exact per-channel inversion of a colored backdrop',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const Color bg = Color(0xFF4CAF50);
    const ValueKey<String> probeKey = ValueKey<String>('probe');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: probeKey,
          child: Stack(
            fit: StackFit.expand,
            children: const [
              ColoredBox(color: bg),
              Center(
                child: DynamicContrastText(
                  'WWWW',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final ByteData rgba = await _capture(tester, probeKey);

    // Every pixel must be either the untouched backdrop, the exact
    // complement (glyph cores), or an anti-aliased mix between the two.
    bool sawComplement = false;
    const int inv0 = 0xFF - 0x4C, inv1 = 0xFF - 0xAF, inv2 = 0xFF - 0x50;
    for (int i = 0; i < 200 * 100 * 4; i += 4) {
      final int r = rgba.getUint8(i);
      final int g = rgba.getUint8(i + 1);
      final int b = rgba.getUint8(i + 2);
      if ((r - inv0).abs() <= 1 && (g - inv1).abs() <= 1 && (b - inv2).abs() <= 1) {
        sawComplement = true;
        break;
      }
    }
    expect(sawComplement, isTrue,
        reason: 'glyph cores must be the exact per-channel complement '
            'of the 0xFF4CAF50 backdrop');
  });
}
