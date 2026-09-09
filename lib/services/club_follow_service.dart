import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'supabase_read_cache.dart';
import 'lazy_content_loader.dart';
import 'guest_session.dart';

class ClubFollowService {
  final Map<String, int> _followedClubRevisions = {};

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  static const _followedClubTtl = Duration(seconds: 60);

  String _cacheKey(String userId) => 'club-following:$userId';

  int followedClubRevisionFor(String userId) =>
      _followedClubRevisions[userId] ?? 0;

  void _invalidateUser(String userId) {
    _followedClubRevisions[userId] = followedClubRevisionFor(userId) + 1;
    supabaseReadCache.invalidate(_cacheKey(userId));
    supabaseReadCache.invalidate('people-profile-details:$userId');
  }

  Future<Set<String>> fetchFollowedClubIds(
    String userId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null || userId.isEmpty) return const {};

    return supabaseReadCache.getOrFetch<Set<String>>(
      key: _cacheKey(userId),
      ttl: _followedClubTtl,
      force: force,
      fetch: () async {
        final rows = await client
            .from('club_followers')
            .select('club_id')
            .eq('profile_id', userId);

        return rows
            .map((row) => (row as Map)['club_id']?.toString() ?? '')
            .where((clubId) => clubId.isNotEmpty)
            .toSet();
      },
    );
  }

  Future<void> followClub({
    required String userId,
    required String clubId,
  }) async {
    final client = _client;
    if (client == null || userId.isEmpty || clubId.isEmpty) return;

    _invalidateUser(userId);

    // Insert-ignoring-duplicate: one round trip instead of check-then-insert,
    // and an existing row (e.g. a board_member role) is left untouched.
    try {
      await client.from('club_followers').insert({
        'profile_id': userId,
        'club_id': clubId,
        'role': 'member',
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') return;
      rethrow;
    }
    // A read that began while the insert was in flight must not become the
    // cache or overwrite the optimistic state after the write commits.
    _invalidateUser(userId);
    supabaseReadCache.invalidate('club-community-count:$clubId');
    supabaseReadCache.invalidate('club-community-members:$clubId');
    lazyContentLoader.invalidateContent();
  }

  Future<void> unfollowClub({
    required String userId,
    required String clubId,
  }) async {
    final client = _client;
    if (client == null || userId.isEmpty || clubId.isEmpty) return;

    _invalidateUser(userId);

    await client
        .from('club_followers')
        .delete()
        .eq('profile_id', userId)
        .eq('club_id', clubId);
    _invalidateUser(userId);
    supabaseReadCache.invalidate('club-community-count:$clubId');
    supabaseReadCache.invalidate('club-community-members:$clubId');
    lazyContentLoader.invalidateContent();
  }

  Future<void> setFollowedClubIds({
    required String userId,
    required Iterable<String> clubIds,
  }) async {
    final client = _client;
    if (client == null || userId.isEmpty) return;

    _invalidateUser(userId);

    await client.from('club_followers').delete().eq('profile_id', userId);
    final rows = clubIds
        .where((clubId) => clubId.isNotEmpty)
        .map(
          (clubId) => {
            'profile_id': userId,
            'club_id': clubId,
            'role': 'member',
          },
        )
        .toList();
    if (rows.isNotEmpty) {
      await client.from('club_followers').insert(rows);
    }
    _invalidateUser(userId);
    // The previous membership set is not available after the replacement, so
    // invalidate all opened-club snapshots rather than risking stale counts
    // for a club that was removed from the new set.
    supabaseReadCache.invalidateWhere(
      (key) =>
          key.startsWith('club-community-count:') ||
          key.startsWith('club-community-members:'),
    );
    lazyContentLoader.invalidateContent();
  }
}

final clubFollowService = ClubFollowService();
