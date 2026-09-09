/// Normalizes a photo the in-app chat camera just captured: upright pixels,
/// and a left-to-right flip when the front lens took it.
///
/// A phone mirrors the front-camera viewfinder, but the file the camera writes
/// is true to life — so a selfie of a sign reads correctly in the file and
/// reversed on the screen the user just framed it on. Chat wants the WhatsApp
/// behaviour: the sent photo matches the viewfinder. [ChatCameraScreen] knows
/// which lens fired and says so, so nothing here has to guess.
///
/// Both lenses go through the same re-encode, because the `camera` plugin
/// writes the sensor's own pixels plus an EXIF orientation tag rather than
/// rotating them (iOS `SavePhotoDelegate.swift` hands over
/// `photo.fileDataRepresentation()` untouched). Baking that rotation into the
/// pixels is the whole reason a rear photo is touched at all.
///
/// Orientation is baked, never written as an EXIF tag, because chat images are
/// delivered through Supabase Storage's image transform
/// (`media_delivery_service.dart`), which re-encodes server-side and drops
/// EXIF. A flag would reach the sender's local preview and nobody else — that
/// version shipped and was pulled the same day (2026-09-02).
///
/// Cost: one JPEG decode and encode per capture, on a background isolate.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// JPEG quality of the re-encoded capture. The camera writes a full-quality
/// JPEG; 90 keeps this single lossy pass from visibly softening it.
const int captureJpegQuality = 90;

/// Returns [bytes] re-encoded upright, mirrored left-to-right when [mirror],
/// or null when [bytes] is not a decodable JPEG.
///
/// The result carries no EXIF at all: the orientation lives in the pixels, so
/// every viewer agrees on it and no downstream transform can drop it.
///
/// Not idempotent when [mirror] is true — a second pass would un-mirror the
/// photo. Call it exactly once per captured file.
Uint8List? normalizeCaptureBytes(
  Uint8List bytes, {
  required bool mirror,
  int quality = captureJpegQuality,
}) {
  try {
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) return null;
    // Upright first, then mirror: mirroring the stored pixels of a rotated
    // capture and keeping its rotation tag is the trap that produced an
    // upside-down photo last time. Baking removes the tag entirely.
    var image = img.bakeOrientation(decoded);
    if (mirror) image = img.flipHorizontal(image);
    image.exif = img.ExifData();
    return img.encodeJpg(
      image,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
  } catch (_) {
    // A decoder that trips over a malformed file must not cost the user the
    // photo; the caller keeps the original.
    return null;
  }
}

/// Rewrites the JPEG at [path] in place with [normalizeCaptureBytes], on a
/// background isolate. Returns whether the file changed.
///
/// Never throws. Any read, decode or write failure leaves the file as the
/// camera saved it: a viewfinder-matching selfie is a nicety, and it must
/// never block sending one.
Future<bool> normalizeCaptureFile(
  String path, {
  required bool mirror,
  int quality = captureJpegQuality,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final sizes = await Isolate.run(
      () => _normalizeInPlace(path, mirror: mirror, quality: quality),
    );
    if (kDebugMode) {
      final verdict = sizes == null
          ? 'left as saved'
          : '${mirror ? 'upright+mirrored' : 'upright'}, '
                '${sizes.$1} -> ${sizes.$2} bytes';
      debugPrint(
        'capture_normalizer: $verdict in ${stopwatch.elapsedMilliseconds} ms',
      );
    }
    return sizes != null;
  } catch (error) {
    debugPrint('capture_normalizer: failed, sending as saved ($error)');
    return false;
  }
}

/// Runs inside the isolate. Returns (bytes in, bytes out), or null when the
/// file could not be read or decoded.
(int, int)? _normalizeInPlace(
  String path, {
  required bool mirror,
  required int quality,
}) {
  final file = File(path);
  final original = file.readAsBytesSync();
  final normalized = normalizeCaptureBytes(
    original,
    mirror: mirror,
    quality: quality,
  );
  if (normalized == null) return null;
  // Write beside the original and rename over it, so an interrupted write
  // leaves a whole file behind rather than half of one.
  final temp = File('$path.normalized.tmp')
    ..writeAsBytesSync(normalized, flush: true);
  temp.renameSync(path);
  return (original.length, normalized.length);
}
