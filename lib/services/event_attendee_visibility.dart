import '../models/event.dart';
import 'account_switcher_service.dart';
import 'auth_service.dart';
import 'club_admin_access.dart';
import 'people_service.dart';
import 'user_state.dart';

/// What the current session is allowed to learn about who is going to an event.
///
/// Three audiences, one rule set:
///
/// * The **hosting club** — a dedicated club login or a student switched into
///   the club account — keeps the full guest list and the real headcount. That
///   is the organiser view the admin screens already render.
/// * A **student** sees only attendees they and the attendee follow each other,
///   plus themselves. The headcount they are shown counts exactly those people,
///   so a number and the faces beside it never disagree; the real turnout stays
///   with the club.
/// * **Anyone else** — another club browsing this event, the ClubUp moderator —
///   gets the headcount and no names at all.
class EventAttendeeVisibility {
  const EventAttendeeVisibility({
    required this.visibleIds,
    required this.count,
    required this.showsNames,
    this.friendsOnly = false,
  });

  /// Attendee ids this session may see by name and face, in the order the
  /// caller supplied. Empty for a session that only gets a number.
  final List<String> visibleIds;

  /// The headcount to render. Equals [visibleIds].length for a student, and
  /// the real total for the hosting club and for name-less sessions.
  final int count;

  /// Whether an attendee list is worth opening at all.
  final bool showsNames;

  /// True when [visibleIds] has been narrowed to the viewer's own friends
  /// rather than being the club's guest list. It decides the framing: a club
  /// is shown "Attendees" and a headcount, a student is shown "Friends going"
  /// and no number at all.
  final bool friendsOnly;

  /// True when there is neither a name nor a number worth drawing.
  bool get isEmpty => count == 0 && visibleIds.isEmpty;
}

/// People the viewer follows who follow them back.
///
/// The follower half of the graph only ever arrives from Supabase
/// ([PeopleService.hydrateFollowing] at startup), while the following half is
/// also restored from local prefs. Offline — and in the window before startup
/// hydration lands — the follower set is empty, so fall back to a one-way
/// follow check rather than showing an empty list. That fallback can never
/// widen past people the viewer already chose to follow.
Set<String> mutuallyFollowedUserIds() {
  final following = userState.followedUserIds;
  final followers = peopleService.cachedFollowerIds;
  if (followers.isEmpty) return following;
  return following.intersection(followers);
}

/// Resolves [attendeeIds] down to what the current session may see for [event].
///
/// [totalCount] is the real turnout when the caller knows it (the Supabase RSVP
/// count can exceed the ids that were hydrated); it defaults to the length of
/// [attendeeIds] and is only ever shown to sessions that may see the total.
EventAttendeeVisibility attendeeVisibilityFor(
  Event event, {
  required Iterable<String> attendeeIds,
  int? totalCount,
}) {
  final ids = attendeeIds.toList(growable: false);
  final total = totalCount ?? ids.length;

  if (currentAccountManagesClubId(event.clubId)) {
    return EventAttendeeVisibility(
      visibleIds: ids,
      count: total,
      showsNames: true,
    );
  }

  if (!authService.isStudentSession ||
      accountSwitcherService.isClubAccountActive) {
    return EventAttendeeVisibility(
      visibleIds: const [],
      count: total,
      showsNames: false,
    );
  }

  final selfId = authService.currentUser?.id ?? '';
  final mutuals = mutuallyFollowedUserIds();
  final visible = ids
      .where((id) => (id.isNotEmpty && id == selfId) || mutuals.contains(id))
      .toList(growable: false);

  return EventAttendeeVisibility(
    visibleIds: visible,
    count: visible.length,
    showsNames: true,
    friendsOnly: true,
  );
}
