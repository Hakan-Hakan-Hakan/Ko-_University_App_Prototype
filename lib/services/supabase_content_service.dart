import 'package:flutter/widgets.dart' show Locale;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import 'locale_service.dart';
import 'mock_data.dart';
import 'mock_clubup_profile.dart';
import 'poll_store.dart';
import 'supabase_config.dart';
import 'supabase_club_service.dart';
import 'user_state.dart';
import 'guest_session.dart';

class StudentEventHistorySnapshot {
  final List<Event> events;
  final Set<String> rsvpEventIds;
  final Set<String> checkinEventIds;

  const StudentEventHistorySnapshot({
    required this.events,
    required this.rsvpEventIds,
    required this.checkinEventIds,
  });

  static const empty = StudentEventHistorySnapshot(
    events: [],
    rsvpEventIds: <String>{},
    checkinEventIds: <String>{},
  );
}

class SupabaseContentService {
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const _eventSelectColumns =
      'id, club_id, title, description, location, image_url, starts_at, '
      'ends_at, image_path, created_by_user_id, tags, registration_url, '
      'schedule, speakers';

  bool _hasAppliedRemoteContent = false;

  // No BuildContext is available this deep in the service layer; these
  // fallback labels are resolved here via the current locale.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(Locale(localeService.languageCode));

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Unit/widget tests and local-only previews can use the in-memory content
      // registries without initializing Supabase first.
      return null;
    }
  }

  Future<bool> refreshPublicContent({bool Function()? shouldApply}) async {
    final client = _client;
    if (client == null) return true;
    final preservedMockClub = clubUpMockClub;
    final includeModerationArchive = await _isPlatformAdmin(client);

    // Keep the shared feed snapshot bounded. Complete historical rows remain in
    // Supabase and are fetched by club/profile only when that history is opened.
    // Filtering on the end time also keeps a long-running live event visible.
    final eventsCutoff = DateTime.now()
        .subtract(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    final results = await Future.wait([
      client
          .from('clubs')
          .select(
            'id, name, short_name, description, logo_url, category_id, email, created_at, club_categories(name)',
          ),
      if (includeModerationArchive)
        _fetchAllRows(client, table: 'events', columns: _eventSelectColumns)
      else
        client
            .from('events')
            .select(_eventSelectColumns)
            .gte('ends_at', eventsCutoff)
            .order('starts_at', ascending: true)
            .limit(500),
      if (includeModerationArchive)
        _fetchAllRows(
          client,
          table: 'club_posts',
          columns:
              'id, club_id, author_id, content, image_url, image_path, created_at',
        )
      else
        client
            .from('club_posts')
            .select(
              'id, club_id, author_id, content, image_url, image_path, created_at',
            )
            .order('created_at', ascending: false)
            .limit(500),
    ]);

    final nextClubs = results[0]
        .map((row) => _clubFromRow(Map<String, dynamic>.from(row as Map)))
        .where((club) => club.id.isNotEmpty)
        .toList();
    await _hydrateBoardMembers(client, nextClubs);
    if (isClubUpMockProfileRegistered && preservedMockClub != null) {
      nextClubs.removeWhere((club) => club.id == preservedMockClub.id);
      nextClubs.add(preservedMockClub);
    }
    final visibleClubIds = nextClubs.map((club) => club.id).toSet();
    final nextEvents = results[1]
        .map((row) => _eventFromRow(Map<String, dynamic>.from(row as Map)))
        .where(
          (event) =>
              event.id.isNotEmpty && visibleClubIds.contains(event.clubId),
        )
        .toList();
    var nextPosts = results[2]
        .map((row) => _postFromRow(Map<String, dynamic>.from(row as Map)))
        .where(
          (post) => post.id.isNotEmpty && visibleClubIds.contains(post.clubId),
        )
        .toList();
    nextPosts = await _attachPolls(client, nextPosts, shouldApply: shouldApply);

    if (shouldApply != null && !shouldApply()) return false;

    // A successful empty response is authoritative for remote rows. The one
    // development-only mock profile was reattached explicitly above; keeping
    // any other previous rows could retain content that RLS filtered out.
    clubs
      ..clear()
      ..addAll(nextClubs);
    events
      ..clear()
      ..addAll(nextEvents);
    newsPosts
      ..clear()
      ..addAll(nextPosts);
    _hasAppliedRemoteContent = true;
    return true;
  }

  /// Resolves a shared event that is not in this device's current feed cache.
  /// A direct id query also covers valid events outside the feed time window.
  Future<Event?> fetchEventById(String eventId) async {
    final normalizedId = eventId.trim();
    if (normalizedId.isEmpty) return null;
    for (final event in events) {
      if (event.id == normalizedId) return event;
    }

    final client = _client;
    if (client == null) return null;
    try {
      final row = await client
          .from('events')
          .select(_eventSelectColumns)
          .eq('id', normalizedId)
          .maybeSingle();
      if (row == null) return null;
      final event = _eventFromRow(Map<String, dynamic>.from(row));
      if (event.id.isEmpty) return null;

      final existingIndex = events.indexWhere(
        (candidate) => candidate.id == event.id,
      );
      if (existingIndex == -1) {
        events.add(event);
      } else {
        events[existingIndex] = event;
      }
      return event;
    } catch (_) {
      return null;
    }
  }

  /// Loads one club into the shared registry even when it is absent from the
  /// bounded feed snapshot. Club-admin screens use this registry for routing,
  /// so they must be able to hydrate their own club directly.
  Future<Club?> fetchClubById(String clubId) async {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) return null;

    final client = _client;
    if (client == null) return clubForId(normalizedClubId);

    final row = await client
        .from('clubs')
        .select(
          'id, name, short_name, description, logo_url, category_id, email, created_at, club_categories(name)',
        )
        .eq('id', normalizedClubId)
        .maybeSingle();
    if (row == null) return null;

    final club = _clubFromRow(Map<String, dynamic>.from(row));
    await _hydrateBoardMembers(client, [club]);
    upsertClub(club);
    return club;
  }

  /// Loads one club's completed events only when its Past filter is opened.
  ///
  /// This avoids expanding the app-wide feed snapshot with every historical
  /// event while still keeping the query bounded by club and end time.
  Future<List<Event>> fetchPastEventsForClub(
    String clubId, {
    DateTime? before,
    int limit = 200,
  }) async {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) return const [];

    final moment = before ?? DateTime.now();
    final cached =
        events
            .where(
              (event) =>
                  event.clubId == normalizedClubId &&
                  !event.endTime.isAfter(moment),
            )
            .toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final client = _client;
    if (client == null) return cached;

    try {
      final rows = await client
          .from('events')
          .select(_eventSelectColumns)
          .eq('club_id', normalizedClubId)
          .lt('ends_at', moment.toUtc().toIso8601String())
          .order('starts_at', ascending: false)
          .limit(limit);
      final fetched = rows
          .map((row) => _eventFromRow(Map<String, dynamic>.from(row as Map)))
          .where((event) => event.id.isNotEmpty)
          .toList();
      await _hydrateEventRsvps(client, fetched);
      _mergeEvents(fetched);
      return fetched;
    } catch (_) {
      // A cached/local result is still useful offline and preserves the current
      // Club Profile behavior if the targeted history read cannot complete.
      return cached;
    }
  }

  /// Fetches only events in the signed-in student's own RSVP/check-in record.
  /// Other profiles continue to use the already-public in-memory activity data.
  Future<StudentEventHistorySnapshot> fetchOwnStudentEventHistory(
    String profileId,
  ) async {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) return StudentEventHistorySnapshot.empty;

    final client = _client;
    // Without an authenticated Supabase client, the global in-memory events
    // already are the source of truth. Do not copy them into the remote cache,
    // which would otherwise outlive a local content refresh/test fixture.
    if (client == null || client.auth.currentUser?.id != normalizedProfileId) {
      return StudentEventHistorySnapshot.empty;
    }

    final participationRows = await Future.wait<List<dynamic>>([
      client
          .from('event_rsvps')
          .select('event_id')
          .eq('profile_id', normalizedProfileId)
          .then<List<dynamic>>((rows) => List<dynamic>.from(rows))
          .catchError((_) => <dynamic>[]),
      client
          .from('event_checkins')
          .select('event_id')
          .eq('profile_id', normalizedProfileId)
          .then<List<dynamic>>((rows) => List<dynamic>.from(rows))
          .catchError((_) => <dynamic>[]),
    ]);
    final rsvpIds = _eventIdsFromRows(participationRows[0]);
    final checkinIds = _eventIdsFromRows(participationRows[1]);
    final eventIds = {...rsvpIds, ...checkinIds}.toList();
    if (eventIds.isEmpty) return StudentEventHistorySnapshot.empty;

    try {
      final rows = await client
          .from('events')
          .select(_eventSelectColumns)
          .inFilter('id', eventIds)
          .order('starts_at', ascending: false);
      final fetched = rows
          .map((row) => _eventFromRow(Map<String, dynamic>.from(row as Map)))
          .where((event) => event.id.isNotEmpty)
          .toList();
      for (final event in fetched) {
        if (rsvpIds.contains(event.id) &&
            !event.attendeeUserIds.contains(normalizedProfileId)) {
          event.attendeeUserIds.add(normalizedProfileId);
        }
      }
      return StudentEventHistorySnapshot(
        events: fetched,
        rsvpEventIds: rsvpIds,
        checkinEventIds: checkinIds,
      );
    } catch (_) {
      return StudentEventHistorySnapshot.empty;
    }
  }

  Set<String> _eventIdsFromRows(List<dynamic> rows) => rows
      .map((row) => (row as Map)['event_id']?.toString() ?? '')
      .where((eventId) => eventId.isNotEmpty)
      .toSet();

  Future<void> _hydrateEventRsvps(
    SupabaseClient client,
    List<Event> targetEvents,
  ) async {
    final eventIds = targetEvents.map((event) => event.id).toList();
    if (eventIds.isEmpty) return;
    try {
      final rows = await client
          .from('event_rsvps')
          .select('event_id, profile_id')
          .inFilter('event_id', eventIds);
      final attendeesByEvent = <String, Set<String>>{};
      for (final row in rows) {
        final raw = row as Map;
        final eventId = raw['event_id']?.toString() ?? '';
        final profileId = raw['profile_id']?.toString() ?? '';
        if (eventId.isEmpty || profileId.isEmpty) continue;
        (attendeesByEvent[eventId] ??= {}).add(profileId);
      }
      for (final event in targetEvents) {
        event.attendeeUserIds
          ..clear()
          ..addAll(attendeesByEvent[event.id] ?? const <String>{});
      }
    } catch (_) {
      // Event history itself is public; attendee visibility is governed by a
      // separate policy and should not prevent the cards from loading.
    }
  }

  void _mergeEvents(List<Event> fetched) {
    for (final event in fetched) {
      final index = events.indexWhere((candidate) => candidate.id == event.id);
      if (index == -1) {
        events.add(event);
        continue;
      }
      if (event.attendeeUserIds.isEmpty) {
        event.attendeeUserIds.addAll(events[index].attendeeUserIds);
      }
      events[index] = event;
    }
  }

  Future<bool> _isPlatformAdmin(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final rows = await client
          .from('app_admins')
          .select('auth_user_id')
          .eq('auth_user_id', userId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Platform moderation must not inherit the public feed's 500-row cap.
  /// UUID keyset pagination keeps each page indexed and avoids OFFSET scans.
  Future<List<dynamic>> _fetchAllRows(
    SupabaseClient client, {
    required String table,
    required String columns,
  }) async {
    const pageSize = 500;
    final result = <dynamic>[];
    String? cursor;

    while (true) {
      var query = client.from(table).select(columns);
      if (cursor != null) query = query.gt('id', cursor);
      final rows = await query.order('id').limit(pageSize);
      result.addAll(rows);
      if (rows.length < pageSize) break;

      final nextCursor = (rows.last as Map)['id']?.toString();
      if (nextCursor == null || nextCursor == cursor) break;
      cursor = nextCursor;
    }
    return result;
  }

  /// Fetches counts only for posts in the current in-memory content snapshot.
  ///
  /// The aggregate view can contain historical rows far beyond the feed. Keep
  /// the request bounded to visible content and split large IN filters into
  /// URL-safe chunks.
  Future<List<dynamic>> _fetchPostLikeCounts(SupabaseClient client) async {
    final postIds = newsPosts
        .map((post) => post.id)
        .where((id) => _uuidPattern.hasMatch(id))
        .toSet()
        .toList();
    if (postIds.isEmpty) return const [];

    final batches = <List<String>>[];
    for (var start = 0; start < postIds.length; start += 200) {
      batches.add(
        postIds.sublist(start, (start + 200).clamp(0, postIds.length)),
      );
    }

    final rowsByBatch = await Future.wait(
      batches.map(
        (postIdBatch) async => List<dynamic>.from(
          await client
              .from('post_like_counts')
              .select('post_id, like_count')
              .inFilter('post_id', postIdBatch),
        ),
      ),
    );
    return rowsByBatch.expand((rows) => rows).toList();
  }

  Future<bool> refreshEngagementCounts({bool Function()? shouldApply}) async {
    final client = _client;
    if (client == null) return true;

    final nextMemberCounts = <String, int>{};
    final nextPostLikeCounts = <String, int>{};
    final nextEventRsvpIds = <String, List<String>>{};

    // The three reads are independent — fire them together instead of one
    // after another. A null result stands in for the branch's old catch
    // fallback, so per-branch degradation is unchanged.
    final eventIds = events.map((e) => e.id).toList();
    final results = await Future.wait<List<dynamic>?>([
      client
          .from('club_member_counts')
          .select('club_id, member_count')
          .then<List<dynamic>?>((rows) => rows)
          .catchError((_) => null),
      _fetchPostLikeCounts(
        client,
      ).then<List<dynamic>?>((rows) => rows).catchError((_) => null),
      if (eventIds.isEmpty)
        Future<List<dynamic>?>.value(const [])
      else
        client
            .from('event_rsvps')
            .select('event_id, profile_id')
            .inFilter('event_id', eventIds)
            .then<List<dynamic>?>((rows) => rows)
            .catchError((_) => null),
    ]);

    final memberRows = results[0];
    if (memberRows != null) {
      for (final row in memberRows) {
        final raw = row as Map;
        final clubId = raw['club_id']?.toString() ?? '';
        final count = int.tryParse(raw['member_count']?.toString() ?? '') ?? 0;
        if (clubId.isNotEmpty) nextMemberCounts[clubId] = count;
      }
    } else {
      nextMemberCounts.addAll(supabaseClubMemberCounts);
    }

    for (final clubId in userState.followedClubIds) {
      final current = nextMemberCounts[clubId] ?? 0;
      if (current < 1) nextMemberCounts[clubId] = 1;
    }

    final likeRows = results[1];
    if (likeRows != null) {
      for (final row in likeRows) {
        final raw = row as Map;
        final postId = raw['post_id']?.toString() ?? '';
        final count = int.tryParse(raw['like_count']?.toString() ?? '') ?? 0;
        if (postId.isNotEmpty) nextPostLikeCounts[postId] = count;
      }
    } else {
      nextPostLikeCounts.addAll(supabasePostLikeCounts);
    }

    // null (fetch failed) keeps existing event attendee ids, as before.
    final rsvpRows = results[2];
    if (rsvpRows != null) {
      for (final row in rsvpRows) {
        final raw = row as Map;
        final eventId = raw['event_id']?.toString() ?? '';
        final profileId = raw['profile_id']?.toString() ?? '';
        if (eventId.isEmpty || profileId.isEmpty) continue;
        (nextEventRsvpIds[eventId] ??= []).add(profileId);
      }
    }

    if (shouldApply != null && !shouldApply()) return false;

    for (final event in events) {
      final attendeeIds = nextEventRsvpIds[event.id];
      if (attendeeIds == null) continue;
      event.attendeeUserIds
        ..clear()
        ..addAll(attendeeIds.toSet());
    }

    supabaseClubMemberCounts
      ..clear()
      ..addAll(nextMemberCounts);
    supabasePostLikeCounts
      ..clear()
      ..addAll(nextPostLikeCounts);
    return true;
  }

  /// Removes only snapshots that came from Supabase.
  ///
  /// RLS-filtered rows from one authenticated account cannot remain visible
  /// while another account signs in.
  void clearSessionContent() {
    if (!_hasAppliedRemoteContent) return;
    clubs.clear();
    events.clear();
    newsPosts.clear();
    supabaseClubMemberCounts.clear();
    supabasePostLikeCounts.clear();
    _hasAppliedRemoteContent = false;
  }

  Club _clubFromRow(Map<String, dynamic> row) {
    final id = _string(row, ['id']);
    final adminIds = _stringList(row['admin_user_ids'] ?? row['adminUserIds']);
    if (adminIds.isEmpty && id.isNotEmpty) adminIds.add(id);
    return Club(
      id: id,
      name: _string(row, ['name', 'title'], fallback: _l10n.clubFallbackName),
      shortName: _nullableString(row, ['short_name', 'shortName']),
      description: _string(row, ['description', 'bio']),
      logoUrl: supabaseClubService.publicLogoUrl(
        _nullableString(row, ['logo_url', 'logoUrl']),
      ),
      categoryId: _nullableString(row, ['category_id', 'categoryId']),
      categoryName: _categoryName(row),
      email: _nullableString(row, ['email']),
      adminUserIds: adminIds,
      createdAt: _date(row, ['created_at', 'createdAt']),
      boardMemberIds: _stringList(
        row['board_member_ids'] ?? row['boardMemberIds'],
      ),
      boardMemberTitles: _stringMap(
        row['board_member_titles'] ?? row['boardMemberTitles'],
      ),
    );
  }

  Future<void> _hydrateBoardMembers(
    SupabaseClient client,
    List<Club> targetClubs,
  ) async {
    if (targetClubs.isEmpty) return;

    List rows;
    try {
      rows = await client
          .from('club_followers')
          .select('club_id, profile_id, role, role_title')
          .eq('role', 'board_member');
    } catch (_) {
      try {
        rows = await client
            .from('club_followers')
            .select('club_id, profile_id, role')
            .eq('role', 'board_member');
      } catch (_) {
        return;
      }
    }

    final byClub = {for (final club in targetClubs) club.id: club};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final club = byClub[row['club_id']?.toString() ?? ''];
      final profileId = row['profile_id']?.toString() ?? '';
      if (club == null || profileId.isEmpty) continue;
      if (!club.boardMemberIds.contains(profileId)) {
        club.boardMemberIds.add(profileId);
      }
      final title = row['role_title']?.toString().trim() ?? '';
      if (title.isNotEmpty) club.boardMemberTitles[profileId] = title;
    }
  }

  String? _categoryName(Map<String, dynamic> row) {
    final direct = _nullableString(row, ['category_name', 'categoryName']);
    if (direct != null) return direct;

    final category = row['club_categories'] ?? row['category'];
    if (category is Map) {
      return _nullableString(Map<String, dynamic>.from(category), ['name']);
    }
    return null;
  }

  Event _eventFromRow(Map<String, dynamic> row) {
    final start = _date(row, ['starts_at', 'date_time', 'dateTime']);
    final end =
        _date(row, ['ends_at', 'end_time', 'endTime']) ??
        start?.add(const Duration(hours: 2));

    return Event(
      id: _string(row, ['id']),
      clubId: _string(row, ['club_id', 'clubId']),
      title: _string(row, [
        'title',
        'name',
      ], fallback: _l10n.eventFallbackTitle),
      description: _string(row, ['description']),
      location: _string(row, [
        'location',
      ], fallback: _l10n.campusFallbackLocation),
      dateTime: start ?? DateTime.now(),
      endTime: end ?? DateTime.now().add(const Duration(hours: 2)),
      attendeeUserIds: _stringList(
        row['attendee_user_ids'] ?? row['attendeeUserIds'],
      ),
      rsvpTimestamps: _stringMap(
        row['rsvp_timestamps'] ?? row['rsvpTimestamps'],
      ),
      imagePath: _eventImagePath(row),
      createdByUserId: _nullableString(row, [
        'created_by_user_id',
        'createdByUserId',
        'created_by',
      ]),
      tags: _stringList(row['tags']),
      guestSpeaker: _nullableString(row, ['guest_speaker', 'guestSpeaker']),
      accentColorHex: _nullableString(row, [
        'accent_color_hex',
        'accentColorHex',
      ]),
      registrationUrl: _nullableString(row, [
        'registration_url',
        'registrationUrl',
      ]),
      capacity: row['capacity'] is int
          ? row['capacity'] as int
          : int.tryParse(row['capacity']?.toString() ?? ''),
      schedule: _eventSchedule(row['schedule']),
      speakers: _eventSpeakers(row['speakers']),
    );
  }

  String? _eventImagePath(Map<String, dynamic> row) {
    final imageUrl = _nullableString(row, ['image_url', 'imageUrl']);
    if (imageUrl != null) return imageUrl;

    final imagePath = _nullableString(row, ['image_path', 'imagePath']);
    final client = _client;
    if (client == null || imagePath == null) return imagePath;
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    return client.storage.from('event-images').getPublicUrl(imagePath);
  }

  List<EventSlot>? _eventSchedule(dynamic raw) {
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((slot) => EventSlot.fromMap(Map<String, dynamic>.from(slot)))
        .toList();
  }

  List<EventSpeaker> _eventSpeakers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (speaker) => EventSpeaker.fromMap(Map<String, dynamic>.from(speaker)),
        )
        .toList();
  }

  NewsPost _postFromRow(Map<String, dynamic> row) {
    return NewsPost(
      id: _string(row, ['id']),
      clubId: _string(row, ['club_id', 'clubId']),
      authorId: _string(row, ['author_id', 'authorId'], fallback: ''),
      content: _string(row, ['content', 'body', 'caption']),
      createdAt:
          _date(row, ['created_at', 'createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      title: _string(row, ['title']),
      taggedClubIds: _stringList(
        row['tagged_club_ids'] ?? row['taggedClubIds'],
      ),
      taggedUserIds: _stringList(
        row['tagged_user_ids'] ?? row['taggedUserIds'],
      ),
      imagePath: _postImagePath(row),
      isAnnouncement:
          row['is_announcement'] == true || row['isAnnouncement'] == true,
    );
  }

  /// Attaches polls to their posts in one query. Missing polls table (older
  /// Supabase project) degrades gracefully to poll-less posts.
  Future<List<NewsPost>> _attachPolls(
    SupabaseClient client,
    List<NewsPost> posts, {
    bool Function()? shouldApply,
  }) async {
    if (posts.isEmpty) return posts;
    try {
      final rows = <dynamic>[];
      final postIds = posts.map((post) => post.id).toList();
      for (var start = 0; start < postIds.length; start += 200) {
        final end = (start + 200).clamp(0, postIds.length);
        rows.addAll(
          await client
              .from('polls')
              .select('id, post_id, question, options')
              .inFilter('post_id', postIds.sublist(start, end)),
        );
      }

      final pollsByPostId = <String, PollData>{};
      for (final row in rows) {
        final map = row as Map;
        final postId = map['post_id']?.toString() ?? '';
        final options = map['options'];
        if (postId.isEmpty || options is! List) continue;
        pollsByPostId[postId] = PollData(
          question: map['question']?.toString() ?? '',
          options: options.map((o) => o.toString()).toList(),
          pollId: map['id']?.toString(),
        );
      }
      if (pollsByPostId.isEmpty) return posts;

      // One batched poll_votes query for every poll on the feed, instead of
      // two queries per poll card at render time.
      await _seedPollVotes(client, pollsByPostId, shouldApply: shouldApply);

      return [
        for (final post in posts)
          pollsByPostId.containsKey(post.id)
              ? NewsPost(
                  id: post.id,
                  clubId: post.clubId,
                  authorId: post.authorId,
                  content: post.content,
                  createdAt: post.createdAt,
                  title: post.title,
                  taggedClubIds: post.taggedClubIds,
                  taggedUserIds: post.taggedUserIds,
                  imagePath: post.imagePath,
                  poll: pollsByPostId[post.id],
                  isAnnouncement: post.isAnnouncement,
                )
              : post,
      ];
    } catch (_) {
      return posts;
    }
  }

  /// Batch-fetches every feed poll's votes in one query and seeds them into
  /// [pollStore], so poll cards render without issuing their own per-card
  /// hydrate queries. Degrades independently of poll attachment.
  Future<void> _seedPollVotes(
    SupabaseClient client,
    Map<String, PollData> pollsByPostId, {
    bool Function()? shouldApply,
  }) async {
    try {
      final postIdByPollId = <String, String>{
        for (final entry in pollsByPostId.entries)
          if (entry.value.pollId != null) entry.value.pollId!: entry.key,
      };
      if (postIdByPollId.isEmpty) return;

      final rows = <dynamic>[];
      final pollIds = postIdByPollId.keys.toList();
      for (var start = 0; start < pollIds.length; start += 200) {
        final end = (start + 200).clamp(0, pollIds.length);
        rows.addAll(
          await client
              .from('poll_votes')
              .select('poll_id, profile_id, option_index')
              .inFilter('poll_id', pollIds.sublist(start, end)),
        );
      }

      final votesByPostId = <String, Map<String, int>>{
        for (final postId in pollsByPostId.keys) postId: {},
      };
      for (final row in rows) {
        final map = row as Map;
        final postId = postIdByPollId[map['poll_id']?.toString() ?? ''];
        final profileId = map['profile_id']?.toString() ?? '';
        final optionIndex = map['option_index'];
        if (postId == null || profileId.isEmpty || optionIndex is! int) {
          continue;
        }
        votesByPostId[postId]![profileId] = optionIndex;
      }
      if (shouldApply != null && !shouldApply()) return;
      pollStore.seedRemoteVotes(votesByPostId);
    } catch (_) {
      // Poll cards fall back to their own lazy hydrate.
    }
  }

  String? _postImagePath(Map<String, dynamic> row) {
    final imageUrl = _nullableString(row, ['image_url', 'imageUrl']);
    if (imageUrl != null) return imageUrl;

    final imagePath = _nullableString(row, ['image_path', 'imagePath']);
    final client = _client;
    if (client == null || imagePath == null) return imagePath;
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    return client.storage.from('post-images').getPublicUrl(imagePath);
  }

  String _string(
    Map<String, dynamic> row,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  String? _nullableString(Map<String, dynamic> row, List<String> keys) {
    final value = _string(row, keys);
    return value.isEmpty ? null : value;
  }

  DateTime? _date(Map<String, dynamic> row, List<String> keys) {
    final value = _nullableString(row, keys);
    return tryParseEventDateTime(value);
  }

  List<String> _stringList(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is List) return raw.map((value) => value.toString()).toList();
    return raw
        .toString()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return <String, String>{};
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }
}

final supabaseContentService = SupabaseContentService();
