import 'package:flutter/widgets.dart' show Locale;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import '../models/notification.dart';
import '../models/user.dart';
import 'auth_service.dart';
import 'locale_service.dart';
import 'mock_data.dart';
import 'supabase_config.dart';
import 'user_state.dart';
import 'guest_session.dart';

/// Generates in-app notifications for club followers when new content is published.
///
/// Recipient IDs come from Supabase. The currently logged-in account's local
/// follow state is also respected while an optimistic follow is being synced.
class ClubNotificationService {
  // No BuildContext is available this deep in the service layer; these
  // generated in-app notification messages are resolved here via the
  // current locale.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(Locale(localeService.languageCode));

  // ── Recipient resolution ─────────────────────────────────────────────────────

  /// Returns the user IDs that should receive a notification for [clubId],
  /// excluding [excludeUserId] (the author/admin who created the content).
  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  Future<List<String>> _recipientIds(
    String clubId,
    String excludeUserId,
  ) async {
    final ids = <String>{};

    final client = _client;
    if (client != null) {
      try {
        final rows = await client
            .from('club_followers')
            .select('profile_id')
            .eq('club_id', clubId);
        ids.addAll(
          rows
              .map((row) => row['profile_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
      } catch (_) {
        // The current user's optimistic local follow is handled below.
      }
    }

    // Include locally registered users until their follow state is synced.
    for (final user in users) {
      if (user.subscribedClubIds.contains(clubId)) {
        ids.add(user.id);
      }
    }

    // Source 2 — runtime follows of the currently logged-in user.
    final loggedInId =
        authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
    if (loggedInId.isNotEmpty && userState.followedClubIds.contains(clubId)) {
      ids.add(loggedInId);
    }

    // Exclude the content author and guard against empty string.
    ids.remove(excludeUserId);
    ids.remove('');

    return ids.toList();
  }

  /// Returns true if a notification with [notifId] already exists,
  /// preventing duplicate delivery for the same content/user pair.
  bool _alreadyNotified(String notifId) =>
      userState.dynamicNotifications.any((n) => n.id == notifId);

  /// Inserts [n] into the dynamic notification list, increments the
  /// unread counter only for the currently logged-in user, and persists.
  void _emit(AppNotification n) {
    userState.addNotification(n);
  }

  String? _clubNotificationUserId(String clubId) {
    for (final admin in clubAdmins) {
      if (admin.id == clubId) return admin.id;
    }

    Club? club;
    for (final candidate in clubs) {
      if (candidate.id == clubId) {
        club = candidate;
        break;
      }
    }
    return club != null && club.adminUserIds.isNotEmpty
        ? club.adminUserIds.first
        : clubId;
  }

  String _actorName(String userId) {
    User? user;
    for (final candidate in users) {
      if (candidate.id == userId) {
        user = candidate;
        break;
      }
    }
    if (user != null) return user.name;
    final currentUser = authService.currentUser;
    if (currentUser?.id == userId) return currentUser!.name;
    return _l10n.studentFallbackName;
  }

  // ── Public API ────────────────────────────────────────────────────────────────

  /// Notifies all followers of [post.clubId] that a new post was published.
  Future<void> notifyFollowersAboutPost(NewsPost post) async {
    final club = clubs.firstWhere(
      (c) => c.id == post.clubId,
      orElse: () => clubs.first,
    );
    for (final userId in await _recipientIds(post.clubId, post.authorId)) {
      final notifId = 'club_post_${post.id}_$userId';
      if (_alreadyNotified(notifId)) continue;
      _emit(
        AppNotification(
          id: notifId,
          userId: userId,
          message: _l10n.clubSharedNewPost(club.name),
          createdAt: DateTime.now(),
          targetType: 'post',
          targetId: post.id,
          fromId: post.clubId,
        ),
      );
    }
  }

  /// Notifies all followers of [event.clubId] that a new event was created.
  Future<void> notifyFollowersAboutEvent(Event event) async {
    final club = clubs.firstWhere(
      (c) => c.id == event.clubId,
      orElse: () => clubs.first,
    );
    final authorId = event.createdByUserId ?? '';
    for (final userId in await _recipientIds(event.clubId, authorId)) {
      final notifId = 'club_event_${event.id}_$userId';
      if (_alreadyNotified(notifId)) continue;
      _emit(
        AppNotification(
          id: notifId,
          userId: userId,
          message: _l10n.clubPostedNewEvent(club.name, event.title),
          createdAt: DateTime.now(),
          targetType: 'event',
          targetId: event.id,
          fromId: event.clubId,
        ),
      );
    }
  }

  /// Notifies every user @-mentioned in [post] that they were tagged.
  /// Mentioned clubs are notified through their club notification account.
  void notifyMentionedUsers(NewsPost post) {
    final club = clubs.firstWhere(
      (c) => c.id == post.clubId,
      orElse: () => clubs.first,
    );

    final recipientIds = <String>{...post.taggedUserIds};
    for (final clubId in post.taggedClubIds) {
      final clubRecipient = _clubNotificationUserId(clubId);
      if (clubRecipient != null) recipientIds.add(clubRecipient);
    }
    recipientIds.remove(post.authorId);
    recipientIds.remove('');

    for (final userId in recipientIds) {
      final notifId = 'mention_${post.id}_$userId';
      if (_alreadyNotified(notifId)) continue;
      _emit(
        AppNotification(
          id: notifId,
          userId: userId,
          message: _l10n.clubMentionedYouInPost(club.name),
          createdAt: DateTime.now(),
          targetType: 'post',
          targetId: post.id,
          fromId: post.clubId,
        ),
      );
    }
  }

  void notifyClubAboutPostLike({
    required NewsPost post,
    required String actorUserId,
  }) {
    final recipientId = _clubNotificationUserId(post.clubId);
    if (recipientId == null || recipientId == actorUserId) return;

    final notifId = 'post_like_${post.id}_$actorUserId';
    if (_alreadyNotified(notifId)) return;
    _emit(
      AppNotification(
        id: notifId,
        userId: recipientId,
        message: _l10n.actorLikedYourPost(_actorName(actorUserId)),
        createdAt: DateTime.now(),
        targetType: 'post',
        targetId: post.id,
        fromId: actorUserId,
      ),
    );
  }

  /// Notifies the club account that a student commented on its post.
  /// Unlike likes, repeat comments notify again (each has a unique timestamp).
  void notifyClubAboutComment({
    required NewsPost post,
    required String actorUserId,
  }) {
    final recipientId = _clubNotificationUserId(post.clubId);
    if (recipientId == null || recipientId == actorUserId) return;

    final notifId =
        'post_comment_${post.id}_${actorUserId}_'
        '${DateTime.now().millisecondsSinceEpoch}';
    _emit(
      AppNotification(
        id: notifId,
        userId: recipientId,
        message: _l10n.actorCommentedOnYourPost(_actorName(actorUserId)),
        createdAt: DateTime.now(),
        targetType: 'post',
        targetId: post.id,
        fromId: actorUserId,
      ),
    );
  }

  void notifyClubAboutEventRsvp({
    required Event event,
    required String actorUserId,
  }) {
    final recipientId = _clubNotificationUserId(event.clubId);
    if (recipientId == null || recipientId == actorUserId) return;

    final notifId = 'event_rsvp_${event.id}_$actorUserId';
    if (_alreadyNotified(notifId)) return;
    _emit(
      AppNotification(
        id: notifId,
        userId: recipientId,
        message: _l10n.actorRsvpdToEvent(_actorName(actorUserId), event.title),
        createdAt: DateTime.now(),
        targetType: 'event',
        targetId: event.id,
        fromId: actorUserId,
      ),
    );
  }
}

final clubNotificationService = ClubNotificationService();
