import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../models/comment.dart';
import '../models/event.dart';
import '../models/user.dart';
import 'feed_v2_service.dart';
import 'people_service.dart';
import 'supabase_config.dart';
import 'supabase_read_cache.dart';
import 'guest_session.dart';
import 'mock_data.dart';

class SupabaseInteractionService {
  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Widget/unit tests and local-only previews may not bootstrap Supabase.
      return null;
    }
  }

  static const _identityTtl = Duration(seconds: 60);
  static const _engagementTtl = Duration(seconds: 30);
  static const _threadTtl = Duration(seconds: 10);
  static const _postLikerPreviewTtl = Duration(seconds: 30);

  final Map<String, List<User>> _postLikerPreviewCache = {};
  final Map<String, DateTime> _postLikerPreviewFetchedAt = {};
  final Map<String, Future<List<User>>> _postLikerPreviewInFlight = {};
  final Map<String, Completer<List<User>>> _postLikerPreviewWaiters = {};
  final Set<String> _pendingPostLikerPreviewIds = {};
  bool _postLikerPreviewFlushScheduled = false;
  int _postLikerPreviewGeneration = 0;

  String _key(String type, String id) => '$type:$id';

  String _batchKey(String type, Iterable<String> ids) {
    final normalized = ids.where((id) => id.isNotEmpty).toSet().toList()
      ..sort();
    return '$type:${normalized.join(',')}';
  }

  void _invalidateBatch(String type, String id) {
    supabaseReadCache.invalidateWhere((key) {
      if (!key.startsWith('$type:')) return false;
      return key.substring(type.length + 1).split(',').contains(id);
    });
  }

  /// Invalidates all read snapshots whose source is a deleted post.
  ///
  /// Per-user liked-post sets are also cleared because they are batched by
  /// profile and may still contain the removed post id.
  void invalidatePostCaches(String postId) {
    if (postId.isEmpty) return;
    _invalidatePostLikerPreview(postId);
    supabaseReadCache.invalidateWhere((key) {
      if (key.startsWith('liked-posts:')) return true;
      return key.endsWith(':$postId') ||
          (key.contains(':') &&
              key.split(':').last.split(',').contains(postId));
    });
  }

  void _invalidatePostLikerPreview(String postId) {
    _postLikerPreviewCache.remove(postId);
    _postLikerPreviewFetchedAt.remove(postId);
  }

  /// Clears preview state at an authentication boundary so one account's
  /// RLS-visible liker names cannot appear for another account.
  void clearPostLikerPreviewCaches() {
    _postLikerPreviewGeneration++;
    _postLikerPreviewCache.clear();
    _postLikerPreviewFetchedAt.clear();
    _pendingPostLikerPreviewIds.clear();
    for (final waiter in _postLikerPreviewWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(const []);
    }
    _postLikerPreviewWaiters.clear();
    _postLikerPreviewInFlight.clear();
  }

  /// Seeds the one-profile preview already composed into Feed v2 cards. A
  /// mounted card can then render without issuing a follow-up liker query.
  void seedFeedLikerPreviews(Map<String, User?> previews) {
    final now = DateTime.now();
    for (final entry in previews.entries) {
      _postLikerPreviewCache[entry.key] = entry.value == null
          ? const []
          : [entry.value!];
      _postLikerPreviewFetchedAt[entry.key] = now;
    }
  }

  Future<Set<String>> fetchLikedPostIds(
    String profileId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || profileId.isEmpty) return const {};

    return supabaseReadCache.getOrFetch<Set<String>>(
      key: _key('liked-posts', profileId),
      ttl: _identityTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('post_likes')
            .select('post_id')
            .eq('profile_id', profileId);

        return rows
            .map((row) => (row as Map)['post_id']?.toString() ?? '')
            .where((postId) => postId.isNotEmpty)
            .toSet();
      },
    );
  }

  Future<void> setPostLiked({
    required String profileId,
    required String postId,
    required bool liked,
  }) async {
    final client = _client;
    if (client == null || profileId.isEmpty || postId.isEmpty) return;

    supabaseReadCache.invalidate(_key('liked-posts', profileId));
    supabaseReadCache.invalidate(_key('post-likers', postId));
    _invalidatePostLikerPreview(postId);
    _invalidateBatch('post-like-counts', postId);

    if (liked) {
      await _insertIgnoringDuplicate(client, 'post_likes', {
        'profile_id': profileId,
        'post_id': postId,
      });
    } else {
      await client
          .from('post_likes')
          .delete()
          .eq('profile_id', profileId)
          .eq('post_id', postId);
    }
  }

  /// Returns the first liker used by a feed preview.
  ///
  /// Feed cards request this independently during mounting, so requests that
  /// arrive in the same frame are collected into one query. The result is
  /// deliberately capped because the feed needs at most one profile per post;
  /// the full list remains available from [fetchPostLikers] when tapped.
  Future<List<User>> fetchPostLikerPreview(
    String postId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postId.isEmpty) return const [];

    final fetchedAt = _postLikerPreviewFetchedAt[postId];
    final cached = _postLikerPreviewCache[postId];
    if (!force &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _postLikerPreviewTtl) {
      return cached;
    }

    final inFlight = _postLikerPreviewInFlight[postId];
    if (inFlight != null) return inFlight;

    final waiter = Completer<List<User>>();
    _postLikerPreviewWaiters[postId] = waiter;
    _postLikerPreviewInFlight[postId] = waiter.future;
    _pendingPostLikerPreviewIds.add(postId);
    _schedulePostLikerPreviewFlush();
    return waiter.future;
  }

  void _schedulePostLikerPreviewFlush() {
    if (_postLikerPreviewFlushScheduled) return;
    _postLikerPreviewFlushScheduled = true;
    scheduleMicrotask(() {
      _postLikerPreviewFlushScheduled = false;
      unawaited(_flushPostLikerPreviews());
    });
  }

  Future<void> _flushPostLikerPreviews() async {
    final client = _client;
    final generation = _postLikerPreviewGeneration;
    final postIds = _pendingPostLikerPreviewIds.toList();
    _pendingPostLikerPreviewIds.clear();
    if (client == null || postIds.isEmpty) {
      for (final postId in postIds) {
        _completePostLikerPreview(postId, const []);
      }
      return;
    }

    try {
      final rows = await client
          .from('post_likes')
          .select(
            'post_id, profiles(id, full_name, role, avatar_url, bio, major_id, academic_year_id)',
          )
          .inFilter('post_id', postIds)
          .order('created_at', ascending: true)
          .limit(200);

      // A logout/account switch may have happened while the request was in
      // flight. Do not let that response satisfy the next account's waiters.
      if (generation != _postLikerPreviewGeneration) return;

      final firstProfileByPostId = <String, Map<dynamic, dynamic>>{};
      for (final row in rows) {
        final map = row as Map;
        final postId = map['post_id']?.toString() ?? '';
        final profile = map['profiles'];
        if (postId.isEmpty || profile is! Map) continue;
        firstProfileByPostId.putIfAbsent(
          postId,
          () => Map<dynamic, dynamic>.from(profile),
        );
      }

      final users = await peopleService.usersFromProfileMaps(
        firstProfileByPostId.values.toList(),
      );
      final usersById = {for (final user in users) user.id: user};

      for (final postId in postIds) {
        final profile = firstProfileByPostId[postId];
        final userId = profile?['id']?.toString() ?? '';
        final preview = usersById[userId];
        final result = preview == null ? const <User>[] : [preview];
        _postLikerPreviewCache[postId] = result;
        _postLikerPreviewFetchedAt[postId] = DateTime.now();
        _completePostLikerPreview(postId, result);
      }
    } catch (_) {
      if (generation != _postLikerPreviewGeneration) return;
      for (final postId in postIds) {
        _completePostLikerPreview(postId, const []);
      }
    }
  }

  void _completePostLikerPreview(String postId, List<User> result) {
    final waiter = _postLikerPreviewWaiters.remove(postId);
    _postLikerPreviewInFlight.remove(postId);
    if (waiter != null && !waiter.isCompleted) waiter.complete(result);
  }

  Future<List<User>> fetchPostLikers(
    String postId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postId.isEmpty) return const [];

    return supabaseReadCache.getOrFetch<List<User>>(
      key: _key('post-likers', postId),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('post_likes')
            .select(
              'profiles(id, full_name, role, avatar_url, bio, major_id, academic_year_id)',
            )
            .eq('post_id', postId);

        final profiles = rows
            .map((row) => (row as Map)['profiles'])
            .whereType<Map>()
            .toList();
        final users = await peopleService.usersFromProfileMaps(profiles);
        users.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return users;
      },
    );
  }

  Future<List<User>> fetchPostViewers(
    String postId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postId.isEmpty) return const [];

    return supabaseReadCache.getOrFetch<List<User>>(
      key: _key('post-viewers', postId),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('post_views')
            .select(
              'profiles(id, full_name, role, avatar_url, bio, major_id, academic_year_id)',
            )
            .eq('post_id', postId);

        final profiles = rows
            .map((row) => (row as Map)['profiles'])
            .whereType<Map>()
            .toList();
        final users = await peopleService.usersFromProfileMaps(profiles);
        users.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return users;
      },
    );
  }

  Future<Set<String>> fetchRsvpEventIds(
    String profileId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || profileId.isEmpty) return const {};

    return supabaseReadCache.getOrFetch<Set<String>>(
      key: _key('rsvp-events', profileId),
      ttl: _identityTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('event_rsvps')
            .select('event_id')
            .eq('profile_id', profileId);

        return rows
            .map((row) => (row as Map)['event_id']?.toString() ?? '')
            .where((eventId) => eventId.isNotEmpty)
            .toSet();
      },
    );
  }

  /// Resolves an event's attendees from the in-memory registries.
  List<User> _localEventAttendees(String eventId) {
    if (eventId.isEmpty) return const [];
    Event? event;
    for (final candidate in events) {
      if (candidate.id == eventId) {
        event = candidate;
        break;
      }
    }
    if (event == null) return const [];
    final byId = <String, User>{
      for (final user in users) user.id: user,
      for (final user in peopleService.cachedPeople) user.id: user,
    };
    final attendees = <User>[
      for (final id in event.attendeeUserIds)
        if (byId[id] != null) byId[id]!,
    ];
    attendees.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return attendees;
  }

  Future<List<User>> fetchEventAttendees(
    String eventId, {
    bool force = false,
  }) async {
    // Guest mode answers this from the seeded world rather than returning an
    // empty list. Callers treat a completed fetch as authoritative — the event
    // page overwrites both its attendee list and the RSVP count with whatever
    // comes back — so an empty answer here reads as "nobody is going".
    if (guestSession.isActive) return _localEventAttendees(eventId);

    final client = _client;
    if (client == null || eventId.isEmpty) return const [];

    return supabaseReadCache.getOrFetch<List<User>>(
      key: _key('event-attendees', eventId),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('event_rsvps')
            .select(
              'profiles(id, full_name, role, avatar_url, bio, major_id, academic_year_id)',
            )
            .eq('event_id', eventId);

        final profiles = rows
            .map((row) => (row as Map)['profiles'])
            .whereType<Map>()
            .toList();
        final users = await peopleService.usersFromProfileMaps(profiles);
        users.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return users;
      },
    );
  }

  Future<void> setEventRsvp({
    required String profileId,
    required String eventId,
    required bool attending,
  }) async {
    if (profileId.isEmpty || eventId.isEmpty) return;

    // Keep every read surface from restoring the pre-mutation snapshot after
    // the optimistic store update. Feed v2 carries viewer RSVP state inside
    // its cached page, while the other keys hold the profile/attendee reads.
    supabaseReadCache.invalidate(_key('rsvp-events', profileId));
    supabaseReadCache.invalidate(_key('event-attendees', eventId));
    _invalidateBatch('event-rsvp-counts', eventId);
    _invalidateBatch('event-checkin-counts', eventId);
    supabaseFeedV2Service.invalidateFirstPages();

    final client = _client;
    if (client == null) return;

    if (attending) {
      await _insertIgnoringDuplicate(client, 'event_rsvps', {
        'profile_id': profileId,
        'event_id': eventId,
      });
    } else {
      await client
          .from('event_rsvps')
          .delete()
          .eq('profile_id', profileId)
          .eq('event_id', eventId);
    }
  }

  // ── Event check-ins ─────────────────────────────────────────────────────────

  /// Profile ids already checked in to [eventId].
  Future<Set<String>> fetchEventCheckinIds(
    String eventId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || eventId.isEmpty) return const {};

    return supabaseReadCache.getOrFetch<Set<String>>(
      key: _key('event-checkins', eventId),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('event_checkins')
            .select('profile_id')
            .eq('event_id', eventId);

        return rows
            .map((row) => (row as Map)['profile_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      },
    );
  }

  /// Check-in counts for many events in one query (insights).
  Future<Map<String, int>> fetchCheckinCounts(List<String> eventIds) async {
    final client = _client;
    if (client == null || eventIds.isEmpty) return const {};

    final ids = eventIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    return supabaseReadCache.getOrFetch<Map<String, int>>(
      key: _batchKey('event-checkin-counts', ids),
      ttl: _engagementTtl,
      fetch: () async {
        final rows = await client
            .from('event_checkins')
            .select('event_id')
            .inFilter('event_id', ids);

        final counts = <String, int>{};
        for (final row in rows) {
          final eventId = (row as Map)['event_id']?.toString() ?? '';
          if (eventId.isEmpty) continue;
          counts[eventId] = (counts[eventId] ?? 0) + 1;
        }
        return counts;
      },
    );
  }

  Future<void> setEventCheckin({
    required String eventId,
    required String profileId,
    required bool checkedIn,
    String method = 'manual',
  }) async {
    final client = _client;
    if (client == null || eventId.isEmpty || profileId.isEmpty) return;

    supabaseReadCache.invalidate(_key('event-checkins', eventId));
    _invalidateBatch('event-checkin-counts', eventId);

    if (checkedIn) {
      await client.rpc(
        'check_in_event_v2',
        params: {
          'p_event_id': eventId,
          'p_profile_id': profileId,
          'p_method': method,
        },
      );
    } else {
      await client.rpc(
        'remove_event_checkin_v2',
        params: {'p_event_id': eventId, 'p_profile_id': profileId},
      );
    }
  }

  // ── Polls ───────────────────────────────────────────────────────────────────

  Future<String?> _pollIdForPost(SupabaseClient client, String postId) async {
    final row = await client
        .from('polls')
        .select('id')
        .eq('post_id', postId)
        .maybeSingle();
    return row?['id']?.toString();
  }

  /// Remote votes for the poll attached to [postId]: profileId → optionIndex.
  /// A known [pollId] (carried on PollData since content load) skips the
  /// poll-id lookup query.
  Future<Map<String, int>> fetchPollVotes(
    String postId, {
    String? pollId,
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postId.isEmpty) return const {};

    return supabaseReadCache.getOrFetch<Map<String, int>>(
      key: _key('poll-votes', postId),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final resolvedPollId = pollId ?? await _pollIdForPost(client, postId);
        if (resolvedPollId == null) return const <String, int>{};

        final rows = await client
            .from('poll_votes')
            .select('profile_id, option_index')
            .eq('poll_id', resolvedPollId);

        final votes = <String, int>{};
        for (final row in rows) {
          final map = row as Map;
          final profileId = map['profile_id']?.toString() ?? '';
          final optionIndex = map['option_index'];
          if (profileId.isEmpty || optionIndex is! int) continue;
          votes[profileId] = optionIndex;
        }
        return votes;
      },
    );
  }

  /// Records (or changes) a vote on the poll attached to [postId].
  Future<void> upsertPollVote({
    required String postId,
    required int optionIndex,
    String? pollId,
  }) async {
    final client = _client;
    final profileId = client?.auth.currentUser?.id ?? '';
    if (client == null || postId.isEmpty || profileId.isEmpty) return;

    supabaseReadCache.invalidate(_key('poll-votes', postId));

    pollId ??= await _pollIdForPost(client, postId);
    if (pollId == null) return;

    await client.rpc(
      'vote_poll_v2',
      params: {'p_poll_id': pollId, 'p_option_index': optionIndex},
    );
  }

  /// Removes the authenticated caller's vote. The current product UI does not
  /// expose this yet, but keeping the v2 operation here avoids any future need
  /// to reintroduce a caller-supplied voter id.
  Future<void> removePollVote({required String postId, String? pollId}) async {
    final client = _client;
    if (client == null || postId.isEmpty) return;

    supabaseReadCache.invalidate(_key('poll-votes', postId));
    pollId ??= await _pollIdForPost(client, postId);
    if (pollId == null) return;

    await client.rpc('remove_poll_vote_v2', params: {'p_poll_id': pollId});
  }

  // ── Comments ────────────────────────────────────────────────────────────────

  // The live post_comments table has no parent_comment_id: migration 001
  // reserved one for threading but the deployed table never got it, so asking
  // for that column made every comment read and the insert's returning select
  // fail with an undefined-column error. Threading stays a model-level
  // placeholder until the column actually exists.
  Comment _commentFromRow(Map row) => Comment(
    id: row['id']?.toString() ?? '',
    postId: row['post_id']?.toString() ?? '',
    userId: row['profile_id']?.toString() ?? '',
    content: row['content']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now(),
    parentCommentId: row['parent_comment_id']?.toString(),
  );

  /// Fetches comments for [postId], oldest first. Commenter profiles are
  /// hydrated into the people cache so names/avatars resolve in the UI.
  Future<List<Comment>> fetchComments(
    String postId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postId.isEmpty) return const [];

    return supabaseReadCache.getOrFetch<List<Comment>>(
      key: _key('post-comments', postId),
      ttl: _threadTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('post_comments')
            .select(
              'id, post_id, profile_id, content, created_at, '
              'profiles(id, full_name, role, avatar_url, bio, major_id, academic_year_id)',
            )
            .eq('post_id', postId)
            .order('created_at', ascending: true);

        final profiles = rows
            .map((row) => (row as Map)['profiles'])
            .whereType<Map>()
            .toList();
        await peopleService.usersFromProfileMaps(profiles);

        return [for (final row in rows) _commentFromRow(row as Map)];
      },
    );
  }

  /// Comment counts for many posts in one query (feed badges).
  Future<Map<String, int>> fetchCommentCounts(
    List<String> postIds, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || postIds.isEmpty) return const {};

    final ids = postIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    return supabaseReadCache.getOrFetch<Map<String, int>>(
      key: _batchKey('post-comment-counts', ids),
      ttl: _engagementTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('post_comments')
            .select('post_id')
            .inFilter('post_id', ids);

        final counts = <String, int>{};
        for (final row in rows) {
          final postId = (row as Map)['post_id']?.toString() ?? '';
          if (postId.isEmpty) continue;
          counts[postId] = (counts[postId] ?? 0) + 1;
        }
        return counts;
      },
    );
  }

  /// Inserts a comment and returns the created row, or null when Supabase is
  /// unavailable (caller keeps its local copy).
  Future<Comment?> addComment({
    required String postId,
    required String profileId,
    required String content,
  }) async {
    final client = _client;
    if (client == null ||
        postId.isEmpty ||
        profileId.isEmpty ||
        content.isEmpty) {
      return null;
    }

    supabaseReadCache.invalidate(_key('post-comments', postId));
    _invalidateBatch('post-comment-counts', postId);

    final row = await client
        .from('post_comments')
        .insert({
          'post_id': postId,
          'profile_id': profileId,
          'content': content,
        })
        .select('id, post_id, profile_id, content, created_at')
        .single();
    return _commentFromRow(row);
  }

  Future<void> deleteComment(String commentId) async {
    final client = _client;
    if (client == null || commentId.isEmpty) return;
    // Request the deleted row back so an RLS-filtered no-op cannot look like
    // a successful delete to the optimistic comment store.
    final deleted = await client
        .from('post_comments')
        .delete()
        .eq('id', commentId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('Comment was not deleted: $commentId');
    }
    supabaseReadCache.invalidateWhere(
      (key) =>
          key.startsWith('post-comments:') ||
          key.startsWith('post-comment-counts:'),
    );
  }

  /// Subscribes to inserts, updates and deletes on [postId]'s comment thread.
  ///
  /// [onChanged] is a signal, not the new row: comment traffic is low enough
  /// that refetching the thread is cheaper to get right than reconstructing it
  /// from payloads, which for a delete carry only the row's own columns and
  /// never the joined commenter profile an insert needs.
  ///
  /// Returns null when Supabase is unavailable, so callers stay usable offline.
  RealtimeChannel? subscribeToComments(
    String postId, {
    required void Function() onChanged,
  }) {
    final client = _client;
    if (client == null || postId.isEmpty) return null;

    final channel = client
        .channel('post-comments:$postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: (_) => onChanged(),
        );
    channel.subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    final client = _client;
    if (client == null) return;
    await client.removeChannel(channel);
  }

  Future<void> _insertIgnoringDuplicate(
    SupabaseClient client,
    String table,
    Map<String, dynamic> values,
  ) async {
    try {
      await client.from(table).insert(values);
    } on PostgrestException catch (error) {
      if (error.code == '23505') return;
      rethrow;
    }
  }
}

final supabaseInteractionService = SupabaseInteractionService();
