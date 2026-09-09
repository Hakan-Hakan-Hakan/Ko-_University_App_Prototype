import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/services/capture_normalizer.dart';

const _frontLens = 'iPhone 15 Pro front camera 2.69mm f/1.9';
const _backLens = 'iPhone 15 Pro back triple camera 6.765mm f/1.78';
const _lensModelTag = 0xA434;

/// The four quadrant colours of the fixture, by name.
const _palette = <String, (int, int, int)>{
  'red': (255, 0, 0),
  'green': (0, 255, 0),
  'blue': (0, 0, 255),
  'yellow': (255, 255, 0),
};

/// A 64x32 image whose quadrants are, reading like a page: red, green /
/// blue, yellow. Every flip and rotation moves them to a distinct place, so a
/// wrong transform cannot pass by accident.
img.Image _quadrants() {
  final image = img.Image(width: 64, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final left = x < image.width ~/ 2;
      final top = y < image.height ~/ 2;
      final (r, g, b) = top
          ? (left ? _palette['red']! : _palette['green']!)
          : (left ? _palette['blue']! : _palette['yellow']!);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// The fixture as a JPEG, optionally stamped with an EXIF orientation and a
/// `LensModel`.
///
/// The lens model is written only to prove it is ignored: the caller now
/// states which lens fired, so nothing sniffs the file for it.
Uint8List _jpeg({int? orientation, String? lensModel}) {
  final image = _quadrants();
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  if (lensModel != null) {
    image.exif.exifIfd[_lensModelTag] = img.IfdValueAscii(lensModel);
  }
  return img.encodeJpg(image, quality: 100);
}

/// Size and the nearest palette colour at the centre of each quadrant of the
/// decoded JPEG, as "WxH TL TR BL BR" so a mismatch reads at a glance.
String _describe(Uint8List jpeg) {
  final image = img.decodeJpg(jpeg)!;
  final w = image.width;
  final h = image.height;
  String nearest(int x, int y) {
    final pixel = image.getPixel(x, y);
    String? best;
    var bestDistance = 1 << 30;
    _palette.forEach((name, rgb) {
      final (r, g, b) = rgb;
      final distance =
          (pixel.r - r) * (pixel.r - r) +
          (pixel.g - g) * (pixel.g - g) +
          (pixel.b - b) * (pixel.b - b);
      if (distance < bestDistance) {
        bestDistance = distance.toInt();
        best = name;
      }
    });
    return best!;
  }

  return '${w}x$h '
      '${nearest(w ~/ 4, h ~/ 4)} ${nearest(3 * w ~/ 4, h ~/ 4)} '
      '${nearest(w ~/ 4, 3 * h ~/ 4)} ${nearest(3 * w ~/ 4, 3 * h ~/ 4)}';
}

/// What the fixture must look like once displayed per its EXIF orientation
/// and then mirrored left-to-right. Produced with Pillow
/// (`ImageOps.exif_transpose` then `ImageOps.mirror`), not derived by hand —
/// a hand-derived orientation table is how an earlier version of this
/// feature flipped selfies upside down.
const _expectedMirrored = <int, String>{
  1: '64x32 green red yellow blue',
  2: '64x32 red green blue yellow',
  3: '64x32 blue yellow red green',
  4: '64x32 yellow blue green red',
  5: '32x64 blue red yellow green',
  6: '32x64 red blue green yellow',
  7: '32x64 green yellow red blue',
  8: '32x64 yellow green blue red',
};

/// Undoes the mirror in a [_describe] string by swapping the left and right
/// quadrant of each row.
///
/// Mirroring is its own inverse, so the upright expectations are derived from
/// the Pillow-checked table above rather than typed out a second time.
String _unmirror(String description) {
  final parts = description.split(' ');
  return '${parts[0]} ${parts[2]} ${parts[1]} ${parts[4]} ${parts[3]}';
}

/// What the fixture must look like once displayed per its EXIF orientation,
/// with no mirror: the rear-camera and gallery case.
final _expectedUpright = <int, String>{
  for (final entry in _expectedMirrored.entries)
    entry.key: _unmirror(entry.value),
};

void main() {
  group('normalizeCaptureBytes', () {
    test('sanity: the fixture and the derived tables agree', () {
      expect(_describe(_jpeg()), '64x32 red green blue yellow');
      // Orientation 1 asks for no transform at all, so an upright pass over
      // the fixture has to leave it exactly as it started. That pins the
      // derivation of the whole upright table.
      expect(_expectedUpright[1], '64x32 red green blue yellow');
    });

    test('mirrors and bakes every orientation upright', () {
      _expectedMirrored.forEach((orientation, expected) {
        final out = normalizeCaptureBytes(
          _jpeg(orientation: orientation),
          mirror: true,
        );
        expect(out, isNotNull, reason: 'orientation $orientation');
        expect(_describe(out!), expected, reason: 'orientation $orientation');
        // No EXIF survives: nothing left for a downstream transform to drop,
        // and no orientation for two viewers to disagree about.
        expect(img.decodeJpg(out)!.exif.imageIfd.hasOrientation, isFalse);
      });
    });

    test('bakes every orientation upright without mirroring', () {
      _expectedUpright.forEach((orientation, expected) {
        final out = normalizeCaptureBytes(
          _jpeg(orientation: orientation),
          mirror: false,
        );
        expect(out, isNotNull, reason: 'orientation $orientation');
        expect(_describe(out!), expected, reason: 'orientation $orientation');
        expect(img.decodeJpg(out)!.exif.imageIfd.hasOrientation, isFalse);
      });
    });

    test('ignores the lens model entirely', () {
      // The old version of this feature sniffed EXIF `LensModel` to guess the
      // lens. The caller states it now, so a front tag must not add a flip and
      // a rear tag must not suppress one.
      for (final lensModel in [_frontLens, _backLens, null]) {
        expect(
          _describe(
            normalizeCaptureBytes(
              _jpeg(orientation: 6, lensModel: lensModel),
              mirror: true,
            )!,
          ),
          _expectedMirrored[6],
          reason: 'lens model $lensModel',
        );
        expect(
          _describe(
            normalizeCaptureBytes(
              _jpeg(orientation: 6, lensModel: lensModel),
              mirror: false,
            )!,
          ),
          _expectedUpright[6],
          reason: 'lens model $lensModel',
        );
      }
    });

    test('treats a capture with no orientation tag as upright', () {
      expect(
        _describe(normalizeCaptureBytes(_jpeg(), mirror: true)!),
        _expectedMirrored[1],
      );
      expect(
        _describe(normalizeCaptureBytes(_jpeg(), mirror: false)!),
        _expectedUpright[1],
      );
    });

    test('an upright pass is idempotent', () {
      final once = normalizeCaptureBytes(
        _jpeg(orientation: 6),
        mirror: false,
      )!;
      final twice = normalizeCaptureBytes(once, mirror: false)!;
      expect(_describe(twice), _describe(once));
    });

    test('a mirrored pass is NOT idempotent, so call it once per file', () {
      // Two flips cancel out. This is why the camera screen mirrors exactly
      // once, before anything else can see the file.
      final original = _jpeg(orientation: 6);
      final once = normalizeCaptureBytes(original, mirror: true)!;
      final twice = normalizeCaptureBytes(once, mirror: true)!;
      expect(_describe(once), _expectedMirrored[6]);
      expect(_describe(twice), _expectedUpright[6]);
    });

    test('honours the quality argument', () {
      final low = normalizeCaptureBytes(
        _jpeg(orientation: 1),
        mirror: true,
        quality: 60,
      )!;
      final high = normalizeCaptureBytes(
        _jpeg(orientation: 1),
        mirror: true,
        quality: 95,
      )!;
      expect(low.length, lessThan(high.length));
    });

    test('leaves anything that is not a decodable JPEG alone', () {
      for (final mirror in [true, false]) {
        expect(
          normalizeCaptureBytes(img.encodePng(_quadrants()), mirror: mirror),
          isNull,
        );
        expect(normalizeCaptureBytes(Uint8List(0), mirror: mirror), isNull);
        expect(
          normalizeCaptureBytes(Uint8List.fromList([1, 2, 3]), mirror: mirror),
          isNull,
        );
      }
    });

    test('never throws on a truncated JPEG', () {
      final full = _jpeg(orientation: 6, lensModel: _frontLens);
      for (var length = 1; length < full.length; length += 61) {
        final truncated = Uint8List.fromList(full.sublist(0, length));
        expect(
          () => normalizeCaptureBytes(truncated, mirror: true),
          returnsNormally,
          reason: 'truncated to $length bytes',
        );
      }
    });
  });

  group('normalizeCaptureFile', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('capture_normalizer');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('mirrors a selfie in place and leaves no temp file', () async {
      final file = File('${temp.path}/selfie.jpg')
        ..writeAsBytesSync(_jpeg(orientation: 6, lensModel: _frontLens));

      expect(await normalizeCaptureFile(file.path, mirror: true), isTrue);

      expect(_describe(file.readAsBytesSync()), _expectedMirrored[6]);
      expect(
        temp.listSync().map((entry) => entry.path),
        [file.path],
        reason: 'no temp file left behind',
      );
    });

    test('bakes a rear capture upright in place', () async {
      final file = File('${temp.path}/photo.jpg')
        ..writeAsBytesSync(_jpeg(orientation: 6, lensModel: _backLens));

      expect(await normalizeCaptureFile(file.path, mirror: false), isTrue);

      expect(_describe(file.readAsBytesSync()), _expectedUpright[6]);
      expect(temp.listSync().map((entry) => entry.path), [file.path]);
    });

    test('reports false for a file that cannot be read', () async {
      expect(
        await normalizeCaptureFile('${temp.path}/missing.jpg', mirror: true),
        isFalse,
      );
    });

    test('leaves a file it cannot decode exactly as it was', () async {
      final original = img.encodePng(_quadrants());
      final file = File('${temp.path}/not-a-jpeg.png')
        ..writeAsBytesSync(original);

      expect(await normalizeCaptureFile(file.path, mirror: true), isFalse);

      expect(file.readAsBytesSync(), original);
      expect(temp.listSync().map((entry) => entry.path), [file.path]);
    });
  });
}
