import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/theme_service.dart';
import '../models/content_audience.dart';
import '../models/event.dart';
import '../models/user.dart';
import '../services/app_colors.dart';
import '../services/auth_service.dart';
import '../services/content_store.dart';
import '../services/event_attendee_visibility.dart';
import '../services/lazy_content_loader.dart';
import '../services/mock_data.dart';
import '../services/people_service.dart';
import '../services/moderation_service.dart';
import '../services/rsvp_store.dart';
import '../services/user_prefs_service.dart';
import '../services/user_state.dart';
import '../services/view_tracker.dart';
import '../onboarding/onboarding_anchors.dart';
import '../widgets/club_avatar.dart';
import '../widgets/clubup_design.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/event_cover_image.dart';
import '../widgets/user_avatar.dart';
import '../widgets/app_motion.dart';
import '../widgets/instagram_refresh_control.dart';
import 'event_detail_screen.dart';
import '../services/content_visibility.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

bool _isDateToday(DateTime dt) {
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}

bool _isDateTomorrow(DateTime dt) {
  final t = DateTime.now().add(const Duration(days: 1));
  return dt.year == t.year && dt.month == t.month && dt.day == t.day;
}

bool _isLive(Event e) {
  final now = DateTime.now();
  return !e.dateTime.isAfter(now) && e.endTime.isAfter(now);
}

Color _clubColor(String clubId) {
  const colors = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
    Color(0xFF558B2F),
    Color(0xFF283593),
    Color(0xFF6D4C41),
    Color(0xFF00695C),
    Color(0xFF4527A0),
    Color(0xFFC62828),
  ];
  final idx = clubOrdinal(clubId);
  return colors[(idx < 0 ? 0 : idx) % colors.length];
}

/// Best-known display name for an attendee id — checks the people directory
/// and the seeded user list before falling back to the raw id, so the avatar
/// always has an initial to draw.
String _attendeeName(String userId) {
  final person =
      peopleService.cachedPeople.cast<User?>().firstWhere(
        (u) => u?.id == userId,
        orElse: () => null,
      ) ??
      users.cast<User?>().firstWhere(
        (u) => u?.id == userId,
        orElse: () => null,
      );
  return userState.displayNameFor(userId, person?.name ?? userId);
}

String _fmt2(int n) => n.toString().padLeft(2, '0');
String _timeStr(DateTime dt) => '${_fmt2(dt.hour)}:${_fmt2(dt.minute)}';

String _shortDay(DateTime d, BuildContext context) {
  if (_isDateToday(d)) return AppLocalizations.of(context)!.today;
  if (_isDateTomorrow(d)) return AppLocalizations.of(context)!.tomorrow;
  return '${DateFormat.E(localeService.languageCode).format(d)} ${d.day}';
}

class ThisWeekScreen extends StatefulWidget {
  /// True only for the instance hosted in the main nav bar's IndexedStack, so
  /// the app tour's RSVP anchor attaches to a single widget — this screen is
  /// also pushed as a route from the home "See all".
  final bool isTutorialHost;

  const ThisWeekScreen({super.key, this.isTutorialHost = false});

  @override
  State<ThisWeekScreen> createState() => _ThisWeekScreenState();
}

class _ThisWeekScreenState extends State<ThisWeekScreen> {
  /// Selected category chip. Empty string is the design's "All" chip.
  String _category = '';
  String _query = '';
  final _searchController = TextEditingController();

  /// Saving an event writes the same `userState.savedPostIds` set the feed and
  /// the event detail already use, which `userPrefsService` persists per user
  /// and Saved items reads back. This card used to keep its own session-only
  /// set instead, so a bookmark here never reached Saved items and was gone on
  /// the next launch.
  void _toggleSaved(String eventId) {
    final userId = authService.currentUser?.id ?? '';
    // Saved items is a student surface; a club session has nowhere to read it.
    if (!authService.isStudentSession || userId.isEmpty) return;
    userState.toggleSave(eventId);
    unawaited(userPrefsService.save(userId));
  }

  @override
  void initState() {
    super.initState();
    _loadEventContent();
    localeService.addListener(_onLocaleChanged);
    themeService.addListener(_onLocaleChanged);
    contentStore.addListener(_onContentChanged);
    final now = DateTime.now();
    final userId =
        authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
    for (final e in events.where(
      (e) =>
          e.endTime.isAfter(now) && !moderationService.isClubBlocked(e.clubId),
    )) {
      rsvpStore.seed(e.id, e.attendeeUserIds.contains(userId));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    localeService.removeListener(_onLocaleChanged);
    themeService.removeListener(_onLocaleChanged);
    contentStore.removeListener(_onContentChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _onContentChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEventContent() async {
    try {
      await lazyContentLoader.ensureContentLoaded();
      if (mounted) setState(() {});
    } catch (_) {
      // Keep local seed events visible if Supabase content is unreachable.
    }
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // Rolling two-year pool — excludes fully-past events, keeps live ones.
  List<Event> get _eventPool {
    final now = DateTime.now();
    final endExclusive = DateTime(
      _today.year + 2,
      _today.month,
      _today.day + 1,
    );
    return events
        .where(
          (e) =>
              clubForId(e.clubId) != null &&
              canViewEvent(e) &&
              e.endTime.isAfter(now) &&
              e.dateTime.isBefore(endExclusive),
        )
        .toList();
  }

  bool _matchesQuery(Event e, String q) {
    if (e.title.toLowerCase().contains(q)) return true;
    if (e.description.toLowerCase().contains(q)) return true;
    if (e.location.toLowerCase().contains(q)) return true;
    if (e.tags.any((tag) => tag.toLowerCase().contains(q))) return true;
    return clubForId(e.clubId)?.name.toLowerCase().contains(q) ?? false;
  }

  List<Event> _results() {
    var list = _eventPool;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      // Search stays inside the two-year upcoming event window.
      list = list.where((e) => _matchesQuery(e, q)).toList();
    }
    if (_category.isNotEmpty) {
      list = list
          .where(
            (e) => e.tags.any(
              (tag) => tag.toLowerCase() == _category.toLowerCase(),
            ),
          )
          .toList();
    }
    list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return list;
  }

  // ── New-events bell ─────────────────────────────────────────────────────────

  String get _viewerId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  DateTime _createdAtForEvent(Event event) {
    if (event.id.startsWith('ev_')) {
      final millis = int.tryParse(event.id.substring(3));
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return event.dateTime;
  }

  bool _isCreatedInApp(Event event) {
    return event.createdByUserId != null || event.id.startsWith('ev_');
  }

  List<Event> _newUnopenedEvents() {
    final viewerId = _viewerId;
    if (viewerId.isEmpty) return [];
    final now = DateTime.now();
    return events.where((event) {
      if (moderationService.isClubBlocked(event.clubId)) return false;
      // Without this the bell would announce an event the student cannot open.
      if (!canViewEvent(event)) return false;
      if (!_isCreatedInApp(event)) return false;
      if (!event.endTime.isAfter(now)) return false;
      return !viewTracker.viewerIds(event.id).contains(viewerId);
    }).toList()..sort(
      (a, b) => _createdAtForEvent(b).compareTo(_createdAtForEvent(a)),
    );
  }

  Future<void> _openNewEventNotifications() async {
    final newEvents = _newUnopenedEvents();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _NewEventsSheet(
        events: newEvents,
        createdAtForEvent: _createdAtForEvent,
        onEventTap: (event) {
          Navigator.pop(sheetContext);
          _openEvent(event);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _openEvent(Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventDetailScreen(event: event, color: _clubColor(event.clubId)),
      ),
    ).then((_) => setState(() {}));
  }

  void _resetFilters() {
    setState(() {
      _category = '';
      _query = '';
      _searchController.clear();
    });
  }

  /// Category chips: the design's "All" plus every tag present on an event in
  /// the pool, so the row only ever offers categories that match something.
  List<String> get _categoryOptions {
    final seen = <String, String>{};
    for (final event in _eventPool) {
      for (final tag in event.tags) {
        final key = tag.trim().toLowerCase();
        if (key.isEmpty) continue;
        seen.putIfAbsent(key, () => tag.trim());
      }
    }
    final tags = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // Pull-to-refresh: re-pull the event list (same gesture as the home feed).
  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final results = _results();
    final newEventCount = _newUnopenedEvents().length;
    final searching = _query.trim().isNotEmpty;
    final categories = _categoryOptions;

    return Scaffold(
      backgroundColor: ClubUpColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(l10n, newEventCount),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  InstagramRefreshControl(onRefresh: _onRefresh),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: KeyedSubtree(
                        // `tut-events-filters` — only on the nav-hosted
                        // instance, so the key is never mounted twice.
                        key: widget.isTutorialHost
                            ? onboardingAnchors.keyFor(
                                OnboardingAnchors.eventsSearch,
                              )
                            : null,
                        child: _searchBar(l10n),
                      ),
                    ),
                  ),
                  if (categories.isNotEmpty)
                    SliverToBoxAdapter(child: _categoryRow(l10n, categories)),
                  if (results.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        searching: searching,
                        hasFilter: _category.isNotEmpty,
                        onReset: _resetFilters,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((ctx, i) {
                          final ev = results[i];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: i < results.length - 1 ? 12 : 0,
                            ),
                            // Listens to userState so a save made on the event
                            // detail or in the Home feed shows here too — the
                            // nav keeps every tab mounted in an IndexedStack,
                            // so this row would otherwise hold a stale icon.
                            child: ListenableBuilder(
                              listenable: userState,
                              builder: (_, _) => _WeekEventRow(
                                key: ValueKey(ev.id),
                                event: ev,
                                color: _clubColor(ev.clubId),
                                bookmarked: userState.isSaved(ev.id),
                                onBookmark: () => _toggleSaved(ev.id),
                                onTap: () => _openEvent(ev),
                                // Anchor the tour's "RSVP" step to the first
                                // card — only on the nav-hosted instance.
                                rsvpAnchorKey: (i == 0 && widget.isTutorialHost)
                                    ? onboardingAnchors.keyFor(
                                        OnboardingAnchors.eventsRsvp,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }, childCount: results.length),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom + 100,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `header-container` — the ClubUp wordmark and the new-events bell, over a
  /// hairline that separates it from the scroller.
  Widget _header(AppLocalizations l10n, int newEventCount) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ClubUpColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          if (Navigator.canPop(context)) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: ClubUpColors.text,
                ),
              ),
            ),
          ],
          Expanded(
            child: Text.rich(
              // Brand wordmark — intentionally not localized.
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Club',
                    style: figtree(
                      size: 22,
                      weight: FontWeight.w800,
                      color: ClubUpColors.accent,
                    ),
                  ),
                  TextSpan(
                    text: 'Up',
                    style: figtree(
                      size: 22,
                      weight: FontWeight.w800,
                      color: ClubUpColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (authService.isStudentSession)
            _HeaderIconBtn(
              icon: Icons.notifications_none_rounded,
              badgeCount: newEventCount,
              onTap: _openNewEventNotifications,
            ),
        ],
      ),
    );
  }

  Widget _searchBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ClubUpColors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: ClubUpColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: figtree(
                size: 14,
                weight: FontWeight.w400,
                color: ClubUpColors.text,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: l10n.searchEventsPosts,
                hintStyle: figtree(
                  size: 14,
                  weight: FontWeight.w400,
                  color: ClubUpColors.muted,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchController.clear();
              }),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: ClubUpColors.muted,
              ),
            ),
        ],
      ),
    );
  }

  /// `categories-container` — "All" plus one chip per tag in the pool.
  Widget _categoryRow(AppLocalizations l10n, List<String> categories) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? ClubUpColors.accent : ClubUpColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? ClubUpColors.accent : ClubUpColors.border,
              ),
            ),
            child: Text(
              label,
              style: figtree(
                size: 13,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : ClubUpColors.text,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          chip(
            l10n.all,
            _category.isEmpty,
            () => setState(() => _category = ''),
          ),
          for (final tag in categories)
            chip(
              tag,
              _category.toLowerCase() == tag.toLowerCase(),
              () => setState(
                () => _category = _category.toLowerCase() == tag.toLowerCase()
                    ? ''
                    : tag,
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekEventRow extends StatelessWidget {
  final Event event;
  final Color color;
  final bool bookmarked;
  final VoidCallback onBookmark;
  final VoidCallback onTap;
  final Key? rsvpAnchorKey;

  const _WeekEventRow({
    super.key,
    required this.event,
    required this.color,
    required this.bookmarked,
    required this.onBookmark,
    required this.onTap,
    this.rsvpAnchorKey,
  });

  /// The `time-pill` caption — the design's "Tonight · 7 PM" / "Sat · All Day".
  /// Day wording and clock format come from the app's own locale helpers so
  /// this stays correct in Turkish, where the mockup's 12-hour "7 PM" is wrong.
  String _whenLabel(BuildContext context) {
    final day = _shortDay(event.dateTime, context);
    if (_isLive(event)) {
      return '$day · ${AppLocalizations.of(context)!.liveNowFilterLabel}';
    }
    return '$day · ${_timeStr(event.dateTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final club = clubForId(event.clubId);
    // A student is only shown the attendees they follow each other with, and
    // the headcount counts exactly those faces. See [attendeeVisibilityFor].
    final attendance = attendeeVisibilityFor(
      event,
      attendeeIds: event.attendeeUserIds,
    );
    final audience = audienceForEvent(event);

    return GestureDetector(
      key: rsvpAnchorKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ClubUpColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ClubUpColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              offset: Offset(0, 4),
              blurRadius: 4,
            ),
          ],
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EventCoverImage(
                  event: event,
                  color: color,
                  width: 100,
                  height: 100,
                  cacheWidth: 200,
                  cacheHeight: 200,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The chip line shares the card's top edge with the
                      // bookmark control, so it keeps the title's 28px gutter,
                      // and it wraps rather than running under it — the
                      // Turkish badge is half again as wide as the English.
                      Padding(
                        padding: const EdgeInsets.only(right: 28),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ClubUpColors.accent.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _whenLabel(context),
                                style: figtree(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: ClubUpColors.accentText,
                                ),
                              ),
                            ),
                            if (audience != ContentAudience.everyone)
                              ContentAudiencePill(
                                key: ValueKey(
                                  'content-audience-pill-${event.id}',
                                ),
                                audience: audience,
                                accent: ClubUpColors.accent,
                                foreground: ClubUpColors.accentText,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Leave room for the bookmark control on the title line.
                      Padding(
                        padding: const EdgeInsets.only(right: 28),
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: figtree(
                            size: 15,
                            weight: FontWeight.w700,
                            color: ClubUpColors.text,
                          ),
                        ),
                      ),
                      if (club != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            ClubAvatar(
                              clubId: club.id,
                              clubName: club.name,
                              color: color,
                              imageUrl: club.logoUrl,
                              size: 16,
                              fontSize: 8,
                              shape: 'circle',
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.hostedByClub(club.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: figtree(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: ClubUpColors.accentText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (attendance.count > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (attendance.visibleIds.isNotEmpty) ...[
                              _AttendeeStack(userIds: attendance.visibleIds),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              AppLocalizations.of(
                                context,
                              )!.goingCount(attendance.count),
                              style: figtree(
                                size: 11,
                                weight: FontWeight.w600,
                                color: ClubUpColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: -1,
              right: -1,
              child: Semantics(
                button: true,
                selected: bookmarked,
                label: AppLocalizations.of(context)!.save,
                child: GestureDetector(
                  key: ValueKey('event-save-${event.id}'),
                  onTap: onBookmark,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 18,
                      color: bookmarked
                          ? ClubUpColors.accentText
                          : ClubUpColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's overlapping attendee avatars — three at 18px, each pulled 6px
/// over the one before it, matching `avatar-stack` in the handoff.
class _AttendeeStack extends StatelessWidget {
  final List<String> userIds;

  const _AttendeeStack({required this.userIds});

  @override
  Widget build(BuildContext context) {
    final shown = userIds.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 18,
      width: 18 + (shown.length - 1) * 12,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 12,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ClubUpColors.card, width: 1.5),
                ),
                child: UserAvatar(
                  userId: shown[i],
                  name: _attendeeName(shown[i]),
                  size: 18,
                  fontSize: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  final bool hasFilter;
  final VoidCallback onReset;

  const _EmptyState({
    required this.searching,
    required this.hasFilter,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing typed and nothing filtered, yet the list is still empty —
    // that means there simply aren't any upcoming events, not that the
    // user's search/filters excluded everything. Show a friendlier nudge
    // instead of "try a different keyword" / a reset button with nothing
    // to reset.
    final trulyEmpty = !searching && !hasFilter;
    final active = searching || hasFilter;
    final String title = trulyEmpty
        ? AppLocalizations.of(context)!.noEventsYet
        : AppLocalizations.of(context)!.noEventsFound;
    final String subtitle = searching
        ? AppLocalizations.of(context)!.tryDifferentKeyword
        : (hasFilter
              ? AppLocalizations.of(context)!.nothingScheduled
              : AppLocalizations.of(context)!.checkBackLater);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GentleFloat(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: Icon(
                  trulyEmpty
                      ? Icons.event_available_rounded
                      : (searching
                            ? Icons.search_off_rounded
                            : Icons.event_busy_rounded),
                  size: 26,
                  color: AppColors.primaryRed,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
                height: 1.5,
              ),
            ),
            if (active) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    borderRadius: BorderRadius.all(Radius.circular(100)),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.resetFilters,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header icon button (bell)
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final VoidCallback? onTap;

  const _HeaderIconBtn({required this.icon, this.badgeCount = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Icon(icon, size: 18, color: AppColors.secondaryText),
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New events bottom sheet (opened from the bell)
// ─────────────────────────────────────────────────────────────────────────────

class _NewEventsSheet extends StatelessWidget {
  final List<Event> events;
  final DateTime Function(Event event) createdAtForEvent;
  final ValueChanged<Event> onEventTap;

  const _NewEventsSheet({
    required this.events,
    required this.createdAtForEvent,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.74,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 30,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.all(Radius.circular(13)),
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.primaryRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.newEvents,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                          letterSpacing: -0.6,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.unopenedEventsCount(events.length),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: events.isEmpty
                ? const _NoNewEventsState()
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 18),
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _NewEventNotificationCard(
                        event: event,
                        createdAt: createdAtForEvent(event),
                        onTap: () => onEventTap(event),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoNewEventsState extends StatelessWidget {
  const _NoNewEventsState();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 26, 28, bottom + 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.all(Radius.circular(22)),
              border: Border.all(color: AppColors.divider),
            ),
            child: Icon(
              Icons.done_all_rounded,
              color: AppColors.primaryRed,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context)!.allCaughtUp,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)!.newEventsHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewEventNotificationCard extends StatelessWidget {
  final Event event;
  final DateTime createdAt;
  final VoidCallback onTap;

  const _NewEventNotificationCard({
    required this.event,
    required this.createdAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final club = clubForId(event.clubId);
    if (club == null) return const SizedBox.shrink();
    final color = _clubColor(event.clubId);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(18)),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 58,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.all(Radius.circular(15)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.MMM(
                      localeService.languageCode,
                    ).format(event.dateTime).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                  Text(
                    '${event.dateTime.day}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _createdLabel(context, createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${club.name} · ${DateFormat.E(localeService.languageCode).format(event.dateTime)} · ${_timeStr(event.dateTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.secondaryText,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _createdLabel(BuildContext context, DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return AppLocalizations.of(context)!.justNow;
    if (diff.inMinutes < 60) {
      return AppLocalizations.of(context)!.minutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return AppLocalizations.of(context)!.hoursAgo(diff.inHours);
    }
    if (diff.inDays < 7) {
      return AppLocalizations.of(context)!.daysAgo(diff.inDays);
    }
    return AppLocalizations.of(context)!.newLabel;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing dot
// ─────────────────────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Opacity-only repaint of a cached child (visually identical for a solid
    // dot) instead of rebuilding the Container every animation tick.
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
