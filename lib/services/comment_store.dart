import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../models/comment.dart';
import '../models/news_post.dart';
import 'auth_service.dart';
import 'content_safety_service.dart';
import 'content_store.dart';
import 'mock_data.dart';
import 'moderation_service.dart';
import 'rate_limit_error.dart';
import 'supabase_interaction_service.dart';

/// Central comment state store.
///
/// Supabase owns the comments; this store is a cache in front of it, not a
/// second source of truth. Writes only count once the server accepts them
/// ([add] throws otherwise), and [hydrate] reconciles against the server so a
/// comment removed elsewhere does not linger here. The Hive copy exists so a
/// thread can still be read offline — never so one can be authored offline.
class CommentStore extends ChangeNotifier {
  final Set<String> _hydratedPostIds = {};

  static final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _looksLikeUuid(String value) => _uuidRe.hasMatch(value);

  bool _visible(Comment comment) => !moderationService.isCommentHidden(comment);

  /// Comments on [postId], oldest first, minus anything this account has
  /// reported or authored by someone it has blocked.
  List<Comment> commentsFor(String postId) =>
      comments.where((c) => c.postId == postId && _visible(c)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Badge count for [postId]. Once this post's comments have been fetched the
  /// local list is authoritative; before that the feed only has the bulk count
  /// query to go on, so the badge falls back to it.
  int countFor(String postId) {
    final local = comments
        .where((c) => c.postId == postId && _visible(c))
        .length;
    if (_hydratedPostIds.contains(postId)) return local;
    final remote = _remoteCounts[postId];
    return remote != null && remote > local ? remote : local;
  }

  /// Reconciles this device's copy of [postId]'s thread with the server.
  ///
  /// The server is treated as the truth for anything it knows about, so a
  /// comment deleted from another device disappears here too. Two kinds of
  /// row survive that replacement: comments on seed posts, which have no
  /// server row to come back from, and the optimistic local copy of a comment
  /// whose insert is still in flight.
  Future<void> hydrate(String postId, {bool force = false}) async {
    if (!force && _hydratedPostIds.contains(postId)) return;
    if (!_looksLikeUuid(postId)) {
      _hydratedPostIds.add(postId);
      return;
    }

    try {
      final remote = await supabaseInteractionService.fetchComments(
        postId,
        force: force,
      );
      final remoteIds = remote.map((c) => c.id).toSet();
      final before = comments.length;
      comments.removeWhere(
        (c) =>
            c.postId == postId &&
            !remoteIds.contains(c.id) &&
            !_isPendingLocal(c),
      );
      final known = comments.map((c) => c.id).toSet();
      comments.addAll(remote.where((c) => !known.contains(c.id)));
      _hydratedPostIds.add(postId);

      if (comments.length != before || remote.isNotEmpty) {
        contentStore.scheduleSave('comments');
        notifyListeners();
      }
    } catch (error) {
      debugPrint('[comments] fetch failed for post $postId: $error');
    }
  }

  /// Optimistic rows carry a `local-` id until Supabase hands back the real
  /// one; a reconcile that raced the insert must not delete them.
  bool _isPendingLocal(Comment comment) => comment.id.startsWith('local-');

  // ── Live thread ─────────────────────────────────────────────────────────────

  RealtimeChannel? _channel;
  String? _watchedPostId;
  Timer? _refetchDebounce;

  /// Keeps [postId]'s thread in sync with the server while it is on screen.
  /// Safe to call for seed posts and offline — it simply does nothing.
  void watch(String postId) {
    if (_watchedPostId == postId) return;
    unawaited(unwatch());
    if (!_looksLikeUuid(postId)) return;

    _watchedPostId = postId;
    _channel = supabaseInteractionService.subscribeToComments(
      postId,
      // Our own insert already applied optimistically and echoes back here;
      // a short debounce collapses that echo, and any burst, into one refetch.
      onChanged: () {
        _refetchDebounce?.cancel();
        _refetchDebounce = Timer(const Duration(milliseconds: 400), () {
          if (_watchedPostId != postId) return;
          unawaited(hydrate(postId, force: true));
        });
      },
    );
  }

  Future<void> unwatch() async {
    _refetchDebounce?.cancel();
    _refetchDebounce = null;
    _watchedPostId = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await supabaseInteractionService.unsubscribe(channel);
    }
  }

  /// Comment counts for many posts in one query, so the feed can show a badge
  /// without fetching each post's comment list. Same shape as the view-count
  /// hydration: repeats inside the TTL are skipped and concurrent callers join
  /// the in-flight fetch.
  static const _countTtl = Duration(minutes: 5);
  final Map<String, int> _remoteCounts = {};
  DateTime? _lastCountHydrate;
  Future<void>? _inFlightCountHydrate;

  Future<void> hydrateCounts(Iterable<String> postIds, {bool force = false}) {
    final last = _lastCountHydrate;
    if (!force && last != null && DateTime.now().difference(last) < _countTtl) {
      return Future.value();
    }
    final inFlight = _inFlightCountHydrate;
    if (inFlight != null) return inFlight;

    final future = _hydrateCounts(postIds, force: force).whenComplete(() {
      _inFlightCountHydrate = null;
    });
    _inFlightCountHydrate = future;
    return future;
  }

  /// Seeds aggregate-only counts returned with a Feed v2 page. This does not
  /// mark comment threads hydrated: opening a thread still performs its own
  /// detail read and Realtime subscription.
  void seedFeedCounts(Map<String, int> counts) {
    if (counts.isEmpty) return;
    _remoteCounts.addAll(counts);
    _lastCountHydrate = DateTime.now();
    notifyListeners();
  }

  Future<void> _hydrateCounts(
    Iterable<String> postIds, {
    bool force = false,
  }) async {
    final ids = postIds.where(_looksLikeUuid).toSet().toList();
    if (ids.isEmpty) return;
    try {
      final counts = await supabaseInteractionService.fetchCommentCounts(
        ids,
        force: force,
      );
      _remoteCounts
        ..addAll({for (final id in ids) id: 0})
        ..addAll(counts);
      _lastCountHydrate = DateTime.now();
      notifyListeners();
    } catch (error) {
      debugPrint('Comment count hydrate failed: $error');
    }
  }

  /// Publishes a comment to `post_comments`.
  ///
  /// A comment is only ever a server row. It is shown optimistically so the
  /// thread feels immediate, but the single success path is Supabase handing
  /// back the inserted row — every other outcome removes the optimistic copy
  /// and throws. Nothing here can leave a comment that exists only on this
  /// device: a device-only comment is invisible to the club, unreachable by
  /// moderation, and would silently vanish on the next reconcile.
  Future<void> add({required NewsPost post, required String content}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final rejection = contentSafetyService.rejectionMessage([trimmed]);
    if (rejection != null) throw ContentSafetyException(rejection);

    final authorId = authService.currentUser?.id ?? '';
    if (authorId.isEmpty) {
      throw const CommentNotDeliveredException('no signed-in student');
    }
    // A post that never reached Supabase (created offline) has no row for a
    // comment to reference, so there is nothing to attach this to.
    if (!_looksLikeUuid(post.id)) {
      throw CommentNotDeliveredException('post id is not a uuid: ${post.id}');
    }

    final local = Comment(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      postId: post.id,
      userId: authorId,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    comments.add(local);
    notifyListeners();

    Comment? saved;
    var reason = 'supabase client unavailable';
    String? userMessage;
    try {
      saved = await supabaseInteractionService.addComment(
        postId: post.id,
        profileId: authorId,
        content: trimmed,
      );
    } catch (error) {
      reason = '$error';
      userMessage = RateLimitInfo.from(error)?.displayMessage;
    }

    if (saved == null) {
      comments.removeWhere((c) => c.id == local.id);
      notifyListeners();
      // Tagged so it is greppable in a running app's console.
      debugPrint('[comments] insert failed for post ${post.id}: $reason');
      throw CommentNotDeliveredException(reason, userMessage);
    }

    final index = comments.indexWhere((c) => c.id == local.id);
    if (index >= 0) comments[index] = saved;
    // Keep the bulk-count fallback honest for a post whose thread this device
    // has never fetched, otherwise the badge ignores what we just wrote until
    // the next count refresh.
    final counted = _remoteCounts[post.id];
    if (counted != null) _remoteCounts[post.id] = counted + 1;
    contentStore.scheduleSave('comments');
    notifyListeners();
  }

  /// Removes a comment locally, then on the server. A failed delete puts the
  /// comment back rather than leaving the author looking at a thread that
  /// disagrees with what everyone else can still see.
  Future<void> remove(Comment comment) async {
    comments.removeWhere((c) => c.id == comment.id);
    final counted = _remoteCounts[comment.postId];
    if (counted != null && counted > 0) {
      _remoteCounts[comment.postId] = counted - 1;
    }
    contentStore.scheduleSave('comments');
    notifyListeners();

    if (!_looksLikeUuid(comment.id)) return;
    try {
      await supabaseInteractionService.deleteComment(comment.id);
    } catch (error) {
      debugPrint('Comment supabase delete failed: $error');
      comments.add(comment);
      if (counted != null) _remoteCounts[comment.postId] = counted;
      contentStore.scheduleSave('comments');
      notifyListeners();
      rethrow;
    }
  }

  /// Drops cached comment hydration at a session boundary.
  void clearSessionState() {
    _hydratedPostIds.clear();
    _remoteCounts.clear();
    notifyListeners();
  }
}

/// Thrown when a comment could not be written to Supabase. The caller has
/// nothing stored locally to fall back on — by design — so it must tell the
/// user the comment did not go through.
///
/// [reason] carries what actually stopped it (a Postgrest error, a missing
/// session, a post with no server row). It is for logs and diagnosis, not for
/// showing to the user verbatim.
class CommentNotDeliveredException implements Exception {
  final String reason;
  final String? userMessage;

  const CommentNotDeliveredException([
    this.reason = 'unknown',
    this.userMessage,
  ]);

  @override
  String toString() => 'Comment was not delivered to the server: $reason';
}

final commentStore = CommentStore();
