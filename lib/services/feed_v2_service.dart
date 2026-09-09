import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_v2.dart';
import 'supabase_config.dart';
import 'supabase_read_cache.dart';
import 'guest_session.dart';

abstract interface class FeedPageV2Source {
  Future<FeedPageV2> fetchPage({
    FeedCursorV2? cursor,
    int limit,
    bool followedOnly,
    bool force,
  });
}

class SupabaseFeedV2Service implements FeedPageV2Source {
  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static const firstPageTtl = Duration(seconds: 60);

  @override
  Future<FeedPageV2> fetchPage({
    FeedCursorV2? cursor,
    int limit = 25,
    bool followedOnly = false,
    bool force = false,
  }) {
    final normalizedLimit = limit.clamp(1, 50).toInt();
    if (cursor != null) {
      return _fetchRemote(
        cursor: cursor,
        limit: normalizedLimit,
        followedOnly: followedOnly,
      );
    }

    return supabaseReadCache.getOrFetch<FeedPageV2>(
      key: 'feed-v2:first:$followedOnly:$normalizedLimit',
      ttl: firstPageTtl,
      force: force,
      shouldCache: (page) => page.items.isNotEmpty,
      fetch: () =>
          _fetchRemote(limit: normalizedLimit, followedOnly: followedOnly),
    );
  }

  Future<FeedPageV2> _fetchRemote({
    FeedCursorV2? cursor,
    required int limit,
    required bool followedOnly,
  }) async {
    final client = _client;
    if (client == null) {
      throw const FeedV2UnavailableException('Supabase client is unavailable');
    }

    final response = await client.rpc(
      'get_feed_page_v2',
      params: {
        'p_limit': limit,
        'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'p_cursor_id': cursor?.id,
        'p_followed_only': followedOnly,
      },
    );
    if (response is! Map) {
      throw const FormatException('Feed v2 returned a non-object response');
    }
    return FeedPageV2.fromJson(Map<String, dynamic>.from(response));
  }

  void invalidateFirstPages() {
    supabaseReadCache.invalidateWhere(
      (key) => key.startsWith('feed-v2:first:'),
    );
  }
}

class FeedV2UnavailableException implements Exception {
  final String message;
  const FeedV2UnavailableException(this.message);

  @override
  String toString() => 'FeedV2UnavailableException: $message';
}

final supabaseFeedV2Service = SupabaseFeedV2Service();
