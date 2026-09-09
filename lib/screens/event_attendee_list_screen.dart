import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/event.dart';
import '../models/user.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/event_attendee_visibility.dart';
import '../services/mock_data.dart';
import '../services/people_service.dart';
import '../services/supabase_interaction_service.dart';
import '../services/user_state.dart';
import '../widgets/user_avatar.dart';
import 'user_profile_screen.dart';

/// Profile-focused attendee list opened from the student event detail.
///
/// It is not a public guest list: [attendeeVisibilityFor] narrows it to the
/// people the viewer and the attendee follow each other with. Organizer-only
/// RSVP timestamps and check-in state stay in the private organizer attendance
/// screen, which is also the only place the full list is shown.
class EventAttendeeListScreen extends StatefulWidget {
  const EventAttendeeListScreen({
    super.key,
    required this.event,
    required this.color,
  });

  final Event event;
  final Color color;

  @override
  State<EventAttendeeListScreen> createState() =>
      _EventAttendeeListScreenState();
}

class _EventAttendeeListScreenState extends State<EventAttendeeListScreen> {
  bool _loading = true;
  List<User>? _remoteAttendees;

  @override
  void initState() {
    super.initState();
    _hydrateAttendees();
  }

  /// Startup already hydrates the viewer's follow graph, but a cold deep-link
  /// can reach this screen while that is still in flight, and the filter must
  /// not be applied against half a graph. Kept off the attendee fetch's path:
  /// [PeopleService] reaches straight for `Supabase.instance` and throws when
  /// the app runs without it, which must not cost this screen its profiles.
  Future<void> _hydrateFollowGraph() async {
    final viewerId = authService.currentUser?.id ?? '';
    if (viewerId.isEmpty) return;
    try {
      await peopleService.hydrateFollowing(viewerId);
    } catch (_) {
      // The one-way fallback in mutuallyFollowedUserIds() covers this.
    }
  }

  Future<void> _hydrateAttendees() async {
    final followGraph = _hydrateFollowGraph();
    try {
      final attendees = await supabaseInteractionService.fetchEventAttendees(
        widget.event.id,
      );
      _remoteAttendees = attendees;
      await peopleService.hydrateProfilesByIds(
        attendees.isEmpty
            ? widget.event.attendeeUserIds
            : attendees.map((user) => user.id),
      );
    } catch (_) {
      // The list remains useful with locally known profiles and initials.
    }
    // Never skipped by the catch above — the filter reads this graph.
    await followGraph;
    if (mounted) setState(() => _loading = false);
  }

  Map<String, User> get _knownPeople => {
    for (final user in users) user.id: user,
    for (final user in peopleService.cachedPeople) user.id: user,
    for (final user in _remoteAttendees ?? const <User>[]) user.id: user,
  };

  User _userFor(String id, String fallbackName) {
    return _knownPeople[id] ??
        User(
          id: id,
          name: fallbackName,
          email: '',
          password: '',
          role: 'student',
          subscribedClubIds: const [],
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final allAttendeeIds =
        (_remoteAttendees?.map((user) => user.id) ??
                widget.event.attendeeUserIds)
            .toSet()
            .toList();
    final visibility = attendeeVisibilityFor(
      widget.event,
      attendeeIds: allAttendeeIds,
    );
    final attendeeIds = visibility.visibleIds;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        // A student gets their friends by name and no headcount at all — not
        // even of the friends, which the list itself already shows. Only a
        // session reading this as a guest list keeps the "N attending" line.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visibility.friendsOnly ? S.friendsGoingTitle : l10n.attendees,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (!visibility.friendsOnly)
              Text(
                l10n.attendingCount(visibility.count),
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: _loading && allAttendeeIds.isNotEmpty
          ? Center(child: CircularProgressIndicator(color: widget.color))
          : attendeeIds.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  // Three different silences: nobody has RSVP'd, none of the
                  // viewer's friends have, or this session never gets names.
                  !visibility.showsNames
                      ? S.attendeesHiddenForClubs
                      : allAttendeeIds.isEmpty
                      ? l10n.noRsvpsYet
                      : S.friendsGoingEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          : ListView.separated(
              key: const ValueKey('event-public-attendee-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: attendeeIds.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 60, color: AppColors.divider),
              itemBuilder: (context, index) {
                final id = attendeeIds[index];
                final user = _userFor(id, l10n.studentProfile);
                final isKnown = _knownPeople.containsKey(id);
                final displayName = userState.displayNameFor(id, user.name);
                final detail = userState.academicSummaryFor(id);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  onTap: isKnown
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: user),
                          ),
                        )
                      : null,
                  leading: UserAvatar(
                    userId: id,
                    name: displayName,
                    size: 46,
                    fontSize: 15,
                    backgroundColor: widget.color.withValues(alpha: 0.14),
                    textColor: widget.color,
                  ),
                  title: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: detail.isEmpty
                      ? null
                      : Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12.5,
                          ),
                        ),
                  trailing: isKnown
                      ? Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.secondaryText,
                        )
                      : null,
                );
              },
            ),
    );
  }
}
