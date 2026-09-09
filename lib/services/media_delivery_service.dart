import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'guest_session.dart';

/// Delivery copies only. [original] always resolves to the canonical object.
enum MediaRendition { thumbnail, feed, screen, original }

/// All avatar surfaces share one thumbnail cache identity, regardless of the
/// widget's rendered size. The client still lays the cached bitmap out at the
/// requested size, while the bounded source is large enough for profile rows
/// and chat avatars on high-density screens.
const double avatarCacheLogicalSize = 128;

@immutable
class MediaDimensions {
  const MediaDimensions({this.width, this.height});

  final int? width;
  final int? height;

  bool get isOriginal => width == null && height == null;
}

/// Picks physical-pixel dimensions from the real layout while bounding each
/// surface. Source metadata is optional; when present it prevents upscaling.
MediaDimensions mediaDimensionsFor({
  required MediaRendition rendition,
  double? logicalWidth,
  double? logicalHeight,
  double devicePixelRatio = 1,
  int? sourceWidth,
  int? sourceHeight,
}) {
  if (rendition == MediaRendition.original) return const MediaDimensions();
  final cap = switch (rendition) {
    MediaRendition.thumbnail => 768,
    MediaRendition.feed => 1600,
    MediaRendition.screen => 2500,
    MediaRendition.original => 2500,
  };
  final dpr = devicePixelRatio.clamp(1.0, 3.0);

  int? dimension(double? logical, int? source) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    var value = (logical * dpr).ceil().clamp(1, cap);
    if (source != null && source > 0) value = value.clamp(1, source);
    return value;
  }

  var width = dimension(logicalWidth, sourceWidth);
  var height = dimension(logicalHeight, sourceHeight);
  // A rendition without a measured constraint still receives a useful bound.
  // Supplying one axis preserves aspect ratio and avoids server-side cropping.
  width ??= height == null ? cap : null;
  return MediaDimensions(width: width, height: height);
}

@immutable
class StorageMediaReference {
  const StorageMediaReference({
    required this.bucket,
    required this.objectPath,
    required this.isPrivate,
    required this.originalUrl,
    this.revision,
  });

  final String bucket;
  final String objectPath;
  final bool isPrivate;
  final String? originalUrl;
  final String? revision;

  static const _knownBuckets = {
    'avatars',
    'club-avatars',
    'post-images',
    'event-images',
    'group-chat-photos',
    'chat-attachments',
  };

  static StorageMediaReference? tryParse(String value) {
    final text = value.trim();
    if (text.startsWith('chat-attachment://')) {
      final path = text.substring('chat-attachment://'.length);
      if (path.isEmpty) return null;
      return StorageMediaReference(
        bucket: 'chat-attachments',
        objectPath: path,
        isPrivate: true,
        originalUrl: null,
        revision: null,
      );
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      final slash = text.indexOf('/');
      if (slash <= 0) return null;
      final bucket = text.substring(0, slash);
      if (!_knownBuckets.contains(bucket)) return null;
      return StorageMediaReference(
        bucket: bucket,
        objectPath: text.substring(slash + 1),
        isPrivate: bucket == 'chat-attachments',
        originalUrl: null,
        revision: null,
      );
    }

    final segments = uri.pathSegments;
    final storageIndex = segments.indexOf('storage');
    if (storageIndex < 0) return null;
    final bucketIndex = segments.indexWhere(
      _knownBuckets.contains,
      storageIndex + 1,
    );
    if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;
    final bucket = segments[bucketIndex];
    final path = segments
        .skip(bucketIndex + 1)
        .map(Uri.decodeComponent)
        .join('/');
    return StorageMediaReference(
      bucket: bucket,
      objectPath: path,
      isPrivate: bucket == 'chat-attachments',
      originalUrl: text,
      revision: uri.queryParameters['v'],
    );
  }

  String stableKey(
    MediaRendition rendition,
    MediaDimensions dimensions, {
    String? actorId,
  }) => [
    if (isPrivate) actorId ?? 'signed-out',
    bucket,
    objectPath,
    rendition.name,
    dimensions.width ?? 'source',
    dimensions.height ?? 'source',
    ?revision,
  ].join(':');
}

@immutable
class ResolvedMedia {
  const ResolvedMedia({
    required this.url,
    required this.cacheKey,
    this.fallbackUrl,
  });

  final String url;
  final String cacheKey;
  final String? fallbackUrl;
}

class MediaDeliveryMetrics {
  int publicRenditions = 0;
  int signedUrlRequests = 0;
  int signedUrlCacheHits = 0;
  int signedUrlInFlightHits = 0;
  int originalRequests = 0;

  Map<String, int> snapshot() => {
    'public_renditions': publicRenditions,
    'signed_url_requests': signedUrlRequests,
    'signed_url_cache_hits': signedUrlCacheHits,
    'signed_url_in_flight_hits': signedUrlInFlightHits,
    'original_requests': originalRequests,
  };
}

typedef PrivateMediaSigner =
    Future<String> Function(
      StorageMediaReference reference,
      MediaRendition rendition,
      MediaDimensions dimensions,
      Duration lifetime,
    );

class MediaDeliveryService {
  MediaDeliveryService({
    SupabaseClient? client,
    PrivateMediaSigner? privateSigner,
    DateTime Function()? now,
  }) : _clientOverride = client,
       _privateSigner = privateSigner,
       _now = now ?? DateTime.now;

  static const signedUrlLifetime = Duration(hours: 1);
  static const _expirySkew = Duration(minutes: 2);
  static const int renditionQuality = 92;

  final SupabaseClient? _clientOverride;
  final PrivateMediaSigner? _privateSigner;
  final DateTime Function() _now;
  final metrics = MediaDeliveryMetrics();
  final Map<String, ({ResolvedMedia media, DateTime expiresAt})> _signed = {};
  final Map<String, Future<ResolvedMedia>> _inFlight = {};

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (_clientOverride != null) return _clientOverride;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  ResolvedMedia resolvePublic({
    required String value,
    required MediaRendition rendition,
    required MediaDimensions dimensions,
  }) {
    final reference = StorageMediaReference.tryParse(value);
    if (reference == null ||
        reference.isPrivate ||
        rendition == MediaRendition.original) {
      metrics.originalRequests++;
      return ResolvedMedia(url: value, cacheKey: value);
    }
    final client = _client;
    if (client == null) return ResolvedMedia(url: value, cacheKey: value);
    metrics.publicRenditions++;
    var transformed = client.storage
        .from(reference.bucket)
        .getPublicUrl(
          reference.objectPath,
          transform: TransformOptions(
            width: dimensions.width,
            height: dimensions.height,
            resize: ResizeMode.contain,
            quality: renditionQuality,
            format: RequestImageFormat.origin,
          ),
        );
    if (reference.revision != null) {
      final uri = Uri.parse(transformed);
      transformed = uri
          .replace(
            queryParameters: {...uri.queryParameters, 'v': reference.revision!},
          )
          .toString();
    }
    return ResolvedMedia(
      url: transformed,
      cacheKey: reference.stableKey(rendition, dimensions),
      fallbackUrl: reference.originalUrl ?? value,
    );
  }

  Future<ResolvedMedia> resolvePrivate({
    required String value,
    required String actorId,
    required MediaRendition rendition,
    required MediaDimensions dimensions,
  }) {
    final reference = StorageMediaReference.tryParse(value);
    if (reference == null || !reference.isPrivate) {
      return Future.value(
        resolvePublic(
          value: value,
          rendition: rendition,
          dimensions: dimensions,
        ),
      );
    }
    final key = reference.stableKey(rendition, dimensions, actorId: actorId);
    final now = _now();
    final cached = _signed[key];
    if (cached != null && cached.expiresAt.isAfter(now.add(_expirySkew))) {
      metrics.signedUrlCacheHits++;
      return Future.value(cached.media);
    }
    final pending = _inFlight[key];
    if (pending != null) {
      metrics.signedUrlInFlightHits++;
      return pending;
    }
    final future = _sign(reference, actorId, rendition, dimensions, key, now);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<ResolvedMedia> resolvePrivateForCurrentAccount({
    required String value,
    required MediaRendition rendition,
    required MediaDimensions dimensions,
  }) {
    return resolvePrivate(
      value: value,
      actorId: _client?.auth.currentUser?.id ?? '',
      rendition: rendition,
      dimensions: dimensions,
    );
  }

  Future<ResolvedMedia> _sign(
    StorageMediaReference reference,
    String actorId,
    MediaRendition rendition,
    MediaDimensions dimensions,
    String key,
    DateTime now,
  ) async {
    final client = _client;
    if (actorId.isEmpty ||
        (_privateSigner == null &&
            (client == null || client.auth.currentUser?.id != actorId))) {
      throw StateError(
        'Private media requires the current authenticated account.',
      );
    }
    metrics.signedUrlRequests++;
    if (rendition == MediaRendition.original) metrics.originalRequests++;
    final url = _privateSigner != null
        ? await _privateSigner(
            reference,
            rendition,
            dimensions,
            signedUrlLifetime,
          )
        : await client!.storage
              .from(reference.bucket)
              .createSignedUrl(
                reference.objectPath,
                signedUrlLifetime.inSeconds,
                transform: rendition == MediaRendition.original
                    ? null
                    : TransformOptions(
                        width: dimensions.width,
                        height: dimensions.height,
                        resize: ResizeMode.contain,
                        quality: renditionQuality,
                        format: RequestImageFormat.origin,
                      ),
              );
    final media = ResolvedMedia(url: url, cacheKey: key);
    _signed[key] = (media: media, expiresAt: now.add(signedUrlLifetime));
    return media;
  }

  void clearAccount(String actorId) {
    _signed.removeWhere((key, _) => key.startsWith('$actorId:'));
    _inFlight.removeWhere((key, _) => key.startsWith('$actorId:'));
  }

  void clearAllPrivate() {
    _signed.clear();
    _inFlight.clear();
  }
}

final mediaDeliveryService = MediaDeliveryService();
