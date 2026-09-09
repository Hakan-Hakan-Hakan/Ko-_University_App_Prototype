import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'event_cleanup_service.dart';
import 'guest_session.dart';
import 'supabase_content_service.dart';
import 'supabase_config.dart';
import 'supabase_interaction_service.dart';
import 'supabase_read_cache.dart';
import 'people_service.dart';
import 'student_activity_service.dart';

typedef GuardedContentRefresh =
    Future<bool> Function(bool Function() shouldApply);
typedef ContentCacheScopeProvider = String Function();

class LazyContentLoader {
  LazyContentLoader({
    Duration contentTtl = const Duration(minutes: 2),
    Duration countsTtl = const Duration(seconds: 30),
    DateTime Function()? now,
    ContentCacheScopeProvider? scopeProvider,
    GuardedContentRefresh? contentRefresh,
    GuardedContentRefresh? countsRefresh,
    Future<void> Function()? cleanupExpiredEvents,
  }) : _contentTtl = contentTtl,
       _countsTtl = countsTtl,
       _now = now ?? DateTime.now,
       _scopeProvider = scopeProvider ?? _supabaseScope,
       _contentRefresh = contentRefresh ?? _refreshPublicContent,
       _countsRefresh = countsRefresh ?? _refreshEngagementCounts,
       _cleanupExpiredEvents =
           cleanupExpiredEvents ?? eventCleanupService.cleanupExpiredEvents;

  final Duration _contentTtl;
  final Duration _countsTtl;
  final DateTime Function() _now;
  final ContentCacheScopeProvider _scopeProvider;
  final GuardedContentRefresh _contentRefresh;
  final GuardedContentRefresh _countsRefresh;
  final Future<void> Function() _cleanupExpiredEvents;

  Future<void>? _contentLoad;
  Future<void>? _countLoad;
  DateTime? _contentLoadedAt;
  DateTime? _countsLoadedAt;
  String? _cacheScope;
  int _generation = 0;

  Future<void> ensureContentLoaded({bool force = false}) {
    // The guest world is already in memory and is the only content there is.
    if (guestSession.isActive) return Future.value();
    final request = _requestContext();
    if (!force && _isFresh(_contentLoadedAt, _contentTtl)) {
      return Future.value();
    }

    final inFlight = _contentLoad;
    if (inFlight != null) return inFlight;

    late final Future<void> future;
    future = _loadContent(request).whenComplete(() {
      if (identical(_contentLoad, future)) _contentLoad = null;
    });
    _contentLoad = future;
    return future;
  }

  Future<void> refreshContent() async {
    _requestContext();
    await ensureContentLoaded(force: true);
    await ensureCountsLoaded(force: true);
  }

  Future<void> ensureCountsLoaded({bool force = false}) {
    if (guestSession.isActive) return Future.value();
    final request = _requestContext();
    if (!force && _isFresh(_countsLoadedAt, _countsTtl)) {
      return Future.value();
    }

    final inFlight = _countLoad;
    if (inFlight != null) return inFlight;

    late final Future<void> future;
    future = _loadCounts(request).whenComplete(() {
      if (identical(_countLoad, future)) _countLoad = null;
    });
    _countLoad = future;
    return future;
  }

  /// Marks the public content snapshot stale after a successful remote write.
  ///
  /// Keep the current in-memory lists so the caller's optimistic/local update
  /// remains visible, but force the next normal load to reconcile with
  /// Supabase. The generation guard also prevents an older refresh that was
  /// already running when the write completed from being applied afterward.
  void invalidateContent() {
    _generation++;
    _contentLoadedAt = null;
    _countsLoadedAt = null;
    _contentLoad = null;
    _countLoad = null;
  }

  /// Drops all request state at an authentication boundary.
  ///
  /// Supabase RLS can return different public rows for different accounts
  /// (for example test-only clubs), so cached snapshots must never survive an
  /// account switch. In-flight responses receive a generation guard and are
  /// ignored if they complete after this call.
  void invalidate({bool clearRemoteContent = true}) {
    _generation++;
    _cacheScope = null;
    _contentLoadedAt = null;
    _countsLoadedAt = null;
    _contentLoad = null;
    _countLoad = null;
    supabaseReadCache.clear();
    supabaseInteractionService.clearPostLikerPreviewCaches();
    peopleService.clearRemoteCaches();
    studentActivityService.clearRemoteHistory();
    if (clearRemoteContent) {
      supabaseContentService.clearSessionContent();
    }
  }

  Future<void> _loadContent(_CacheRequest request) async {
    final applied = await _contentRefresh(() => _requestIsCurrent(request));
    if (!applied || !_requestIsCurrent(request)) return;

    await _cleanupExpiredEvents();
    if (!_requestIsCurrent(request)) return;
    _contentLoadedAt = _now();
    unawaited(ensureCountsLoaded());
  }

  Future<void> _loadCounts(_CacheRequest request) async {
    final applied = await _countsRefresh(() => _requestIsCurrent(request));
    if (applied && _requestIsCurrent(request)) {
      _countsLoadedAt = _now();
    }
  }

  _CacheRequest _requestContext() {
    final scope = _scopeProvider();
    if (_cacheScope != scope) {
      _generation++;
      _cacheScope = scope;
      _contentLoadedAt = null;
      _countsLoadedAt = null;
      _contentLoad = null;
      _countLoad = null;
      supabaseReadCache.clear();
      supabaseInteractionService.clearPostLikerPreviewCaches();
      peopleService.clearRemoteCaches();
      studentActivityService.clearRemoteHistory();
      supabaseContentService.clearSessionContent();
    }
    return _CacheRequest(scope: scope, generation: _generation);
  }

  bool _requestIsCurrent(_CacheRequest request) =>
      request.generation == _generation &&
      request.scope == _cacheScope &&
      request.scope == _scopeProvider();

  bool _isFresh(DateTime? loadedAt, Duration ttl) {
    if (loadedAt == null) return false;
    final age = _now().difference(loadedAt);
    return age.isNegative || age < ttl;
  }

  static String _supabaseScope() {
    if (!SupabaseConfig.isConfigured) return 'local';
    try {
      return Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    } catch (_) {
      return 'local';
    }
  }

  static Future<bool> _refreshPublicContent(bool Function() shouldApply) {
    return supabaseContentService.refreshPublicContent(
      shouldApply: shouldApply,
    );
  }

  static Future<bool> _refreshEngagementCounts(bool Function() shouldApply) {
    return supabaseContentService.refreshEngagementCounts(
      shouldApply: shouldApply,
    );
  }
}

final lazyContentLoader = LazyContentLoader();

class _CacheRequest {
  final String scope;
  final int generation;

  const _CacheRequest({required this.scope, required this.generation});
}
