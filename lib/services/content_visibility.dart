import 'dart:async';

import '../models/content_audience.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import 'auth_service.dart';
import 'club_admin_access.dart';
import 'content_audience_store.dart';
import 'content_store.dart';
import 'mock_clubup_profile.dart';
import 'mock_data.dart';
import 'user_state.dart';

/// Whether the current session may see a given post or event.
///
/// Three audiences, one rule set — and unlike
/// [EventAttendeeVisibility] these are *nested*, so the rules read as a
/// widening series of reasons to say yes:
///
/// * **Everyone** — the default and the overwhelming majority of content. No
///   further questions asked, which is why it is checked first.
/// * **Followers** — the people who asked to hear from this club. Board members
///   follow their own club, so they are inside this tier by construction.
/// * **Board members** — the club's own staff, and nobody else.
///
/// Two sessions always see everything regardless of tier: the **authoring club**
/// (a dedicated club login or a student switched into the club account), because
/// content you wrote vanishing from your own feed is indefensible; and the
/// **ClubUp moderator**, because content a moderator cannot see is content they
/// cannot moderate.
///
/// Everything else fails closed. In particular a `board` check made before
/// `Club.boardMemberIds` has hydrated hides the content rather than showing it —
/// a few hundred milliseconds of a board member's own restricted post being
/// absent on a cold start, in exchange for never leaking one.
///
/// This file deliberately imports no Supabase client and no Supabase service.
/// That is what keeps every rule below unit-testable with no backend, the same
/// discipline `event_attendee_visibility.dart` observes.

/// The tier [post] is currently addressed to.
///
/// Reads the local store first: the model field is rebuilt from server rows on
/// every content refresh and cannot yet carry the choice. See
/// [ContentAudienceStore] for why. When the column ships, this becomes
/// `post.audience`.
ContentAudience audienceForPost(NewsPost post) =>
    contentAudienceStore.audienceFor(post.id) ?? post.audience;

/// The tier [event] is currently addressed to. See [audienceForPost].
ContentAudience audienceForEvent(Event event) =>
    contentAudienceStore.audienceFor(event.id) ?? event.audience;

/// True when the viewer is staff of [clubId] — its admin, or on its board.
///
/// Board membership is checked against the club record rather than the switched
/// account, so a board member browsing on their *personal* account still sees
/// board-tier content without having to switch. That matches how the board chat
/// lane already treats them.
bool viewerIsClubStaff(String clubId) {
  if (currentAccountManagesClubId(clubId)) return true;
  final viewerId =
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
  if (viewerId.isEmpty) return false;
  final club = clubForId(clubId);
  if (club == null) return false;
  return club.boardMemberIds.contains(viewerId) ||
      club.adminUserIds.contains(viewerId);
}

bool _canView(String clubId, ContentAudience audience) {
  if (audience == ContentAudience.everyone) return true;
  if (currentAccountManagesClubId(clubId)) return true;
  if (isClubUpAdmin(authService.currentAdmin)) return true;
  // Staff satisfy both restricted tiers: the tiers nest, and board members
  // follow their own club.
  if (viewerIsClubStaff(clubId)) return true;
  if (audience == ContentAudience.followers) {
    return userState.isFollowing(clubId);
  }
  return false;
}

bool canViewPost(NewsPost post) => _canView(post.clubId, audienceForPost(post));

bool canViewEvent(Event event) =>
    _canView(event.clubId, audienceForEvent(event));

/// Whether to offer the audience picker at all. Only the club publishing the
/// content gets to choose who it reaches.
bool canChooseAudienceForClub(String clubId) =>
    currentAccountManagesClubId(clubId);

/// Retarget an already-published post.
///
/// The single write entry point, so no UI path can persist the choice without
/// also refreshing what is on screen. Returns false when the session is not
/// entitled to change it. Once the setter RPC exists it slots in ahead of the
/// local write and nothing else here changes.
Future<bool> updatePostAudience(NewsPost post, ContentAudience audience) async {
  if (!canChooseAudienceForClub(post.clubId)) return false;
  await contentAudienceStore.setAudience(post.id, audience);
  final index = newsPosts.indexWhere((candidate) => candidate.id == post.id);
  if (index != -1) {
    newsPosts[index] = newsPosts[index].copyWith(audience: audience);
    unawaited(contentStore.saveNewsPosts());
  }
  contentStore.notifyContentChanged();
  return true;
}

/// Retarget an already-published event. See [updatePostAudience].
Future<bool> updateEventAudience(Event event, ContentAudience audience) async {
  if (!canChooseAudienceForClub(event.clubId)) return false;
  await contentAudienceStore.setAudience(event.id, audience);
  final index = events.indexWhere((candidate) => candidate.id == event.id);
  if (index != -1) {
    events[index] = events[index].copyWith(audience: audience);
    unawaited(contentStore.saveEvents());
  }
  contentStore.notifyContentChanged();
  return true;
}
