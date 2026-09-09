import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import 'mock_data.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

/// Tracks who has viewed each post or event.
/// Key: contentId (postId or eventId)
/// Value: Set of userIds
///
/// Stored in Hive box "view_tracker_v1" so views survive logout/restart.
class ViewTracker extends ChangeNotifier {
  static const _boxName = 'view_tracker_v1';
  late Box<dynamic> _box;
  bool _initialized = false;
  final Map<String, int> _remotePostViewCounts = {};

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    // Test processes (flutter drive) don't run Supabase.initialize — treat an
    // uninitialized instance the same as "not configured".
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    _initialized = true;
  }

  // ── Record a view ─────────────────────────────────────────────────────────────

  void recordView(String contentId, String userId, {bool syncRemote = false}) {
    if (guestSession.isActive) return;
    if (userId.isEmpty || !_initialized) return;
    final existing = _viewerIds(contentId);
    if (!existing.contains(userId)) {
      existing.add(userId);
      unawaited(_box.put(contentId, existing.toList()));
      notifyListeners();
    }
    if (syncRemote) _enqueueRemotePostView(contentId, userId);
  }

  // ── Read ──────────────────────────────────────────────────────────────────────

  int viewCount(String contentId) =>
      _remotePostViewCounts[contentId] ?? _viewerIds(contentId).length;

  /// Seeds aggregate-only counts returned with a Feed v2 page. Viewer
  /// identities remain a separate, explicit organizer detail flow.
  void seedFeedViewCounts(Map<String, int> counts) {
    if (counts.isEmpty) return;
    _remotePostViewCounts.addAll(counts);
    _lastPostViewHydrate = DateTime.now();
    notifyListeners();
  }

  // A view, not a copy: callers read this per item inside feed filters, so
  // copying here would put back the per-call allocation _viewerCache removes.
  Set<String> viewerIds(String contentId) =>
      UnmodifiableSetView(_viewerIds(contentId));

  List<User> viewers(String contentId) {
    final ids = _viewerIds(contentId);
    return users.where((u) => ids.contains(u.id)).toList();
  }

  // The feed re-requests view counts on every load; the underlying rows
  // change slowly, so repeats within the TTL are skipped (pull-to-refresh
  // passes force) and concurrent callers join the in-flight fetch.
  DateTime? _lastPostViewHydrate;
  Future<void>? _inFlightHydrate;
  static const _postViewTtl = Duration(minutes: 5);

  Future<void> hydratePostViewCounts(
    Iterable<String> postIds, {
    bool force = false,
  }) {
    final last = _lastPostViewHydrate;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _postViewTtl) {
      return Future.value();
    }
    final inFlight = _inFlightHydrate;
    if (inFlight != null) return inFlight;

    final future = _hydratePostViewCounts(postIds).whenComplete(() {
      _inFlightHydrate = null;
    });
    _inFlightHydrate = future;
    return future;
  }

  Future<void> _hydratePostViewCounts(Iterable<String> postIds) async {
    final client = _client;
    if (client == null) return;

    final ids = postIds.where(_looksLikeUuid).toSet().toList();
    if (ids.isEmpty) return;

    try {
      final rows = await client
          .from('post_views')
          .select('post_id')
          .inFilter('post_id', ids);
      final counts = <String, int>{for (final id in ids) id: 0};
      for (final row in rows) {
        final id = (row as Map)['post_id']?.toString();
        if (id == null || id.isEmpty) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      _remotePostViewCounts.addAll(counts);
      _lastPostViewHydrate = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Keep local Hive counts if Supabase view tracking is unavailable.
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────────

  /// Decoded viewer sets, mirroring the Hive box. Reads happen per item inside
  /// feed filters and sort comparators, so rebuilding a `Set` from the stored
  /// `List` on every call was allocating once per comparison; the box is only
  /// ever written through [recordView], which mutates the cached set in place.
  final Map<String, Set<String>> _viewerCache = {};

  Set<String> _viewerIds(String contentId) {
    if (!_initialized) return {};
    return _viewerCache.putIfAbsent(contentId, () {
      final raw = _box.get(contentId);
      return raw == null ? <String>{} : Set<String>.from(raw as List);
    });
  }

  // Cards mount as the feed scrolls, so views arrive in bursts: a flick past
  // ten posts used to fire ten separate upserts — ten round trips encoded and
  // decoded on the UI isolate mid-gesture, each answering with its own
  // notifyListeners(). They are now coalesced into one batched upsert a beat
  // after scrolling settles, and a post already reported in this run is never
  // re-sent when its card is recycled back into view.
  static const _remoteFlushDelay = Duration(milliseconds: 1200);
  final Set<String> _remoteViewsSent = {};
  final Map<String, String> _pendingRemoteViews = {};
  Timer? _remoteFlushTimer;

  void _enqueueRemotePostView(String contentId, String userId) {
    if (_client == null || !_looksLikeUuid(contentId)) return;
    if (!_remoteViewsSent.add('$contentId|$userId')) return;
    _pendingRemoteViews[contentId] = userId;
    // A fixed window, not a debounce: the first unreported view opens it and
    // everything seen while it is open rides along. Debouncing would let a
    // long uninterrupted scroll postpone the flush indefinitely.
    if (_remoteFlushTimer != null) return;
    _remoteFlushTimer = Timer(_remoteFlushDelay, () {
      _remoteFlushTimer = null;
      unawaited(_flushRemotePostViews());
    });
  }

  Future<void> _flushRemotePostViews() async {
    final client = _client;
    if (client == null || _pendingRemoteViews.isEmpty) return;
    final batch = Map<String, String>.from(_pendingRemoteViews);
    _pendingRemoteViews.clear();

    final viewedAt = DateTime.now().toUtc().toIso8601String();
    try {
      await client.from('post_views').upsert([
        for (final entry in batch.entries)
          {
            'post_id': entry.key,
            'profile_id': entry.value,
            'viewed_at': viewedAt,
          },
      ], onConflict: 'post_id,profile_id');
    } catch (_) {
      // Local tracking already happened; do not disturb the feed. Allow a
      // retry if these posts are seen again later in the session.
      for (final entry in batch.entries) {
        _remoteViewsSent.remove('${entry.key}|${entry.value}');
      }
      return;
    }

    for (final contentId in batch.keys) {
      _remotePostViewCounts[contentId] =
          (_remotePostViewCounts[contentId] ?? _viewerIds(contentId).length)
              .clamp(1, 1 << 31);
    }
    notifyListeners();
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _looksLikeUuid(String value) => _uuidPattern.hasMatch(value);
}

final viewTracker = ViewTracker();
