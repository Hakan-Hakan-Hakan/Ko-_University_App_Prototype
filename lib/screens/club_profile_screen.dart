import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import '../models/user.dart';
import '../navigation/chat_page_route.dart';
import '../services/account_switcher_service.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/club_admin_access.dart';
import '../services/club_follow_helper.dart';
import '../services/club_follow_service.dart';
import '../services/club_role_localization.dart';
import '../services/mock_clubup_profile.dart';
import '../services/mock_data.dart';
import '../services/moderation_service.dart';
import '../services/people_service.dart';
import '../services/user_state.dart';
import '../services/user_prefs_service.dart';
import '../services/content_store.dart';
import '../services/event_access.dart';
import '../services/student_club_role_service.dart';
import '../services/supabase_event_service.dart';
import '../services/supabase_content_service.dart';
import '../services/supabase_post_service.dart';
import '../onboarding/onboarding_anchors.dart';
import '../services/chat_store.dart';
import '../widgets/club_avatar.dart';
import '../widgets/club_follow_button.dart';
import '../widgets/club_profile_design.dart';
import '../widgets/event_cover_image.dart';
import '../widgets/home_design.dart';
import '../widgets/moderation_reason_sheet.dart';
import 'chat_thread_screen.dart';
import 'club_board_members_screen.dart';
import 'club_insights_screen.dart';
import 'club_profile_members_screen.dart';
import 'event_detail_screen.dart';
import 'post_detail_screen.dart';
import 'user_profile_screen.dart';
import 'create_post_screen.dart' show buildPostBanner;
import '../widgets/user_avatar.dart';
import '../models/content_audience.dart';
import '../services/content_visibility.dart';
import '../widgets/content_audience_sheet.dart';

bool _isDarkClubTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _clubPagePanel(BuildContext context) =>
    _isDarkClubTheme(context) ? const Color(0xFF160008) : AppColors.surfaceAlt;

Color _clubPageCard(BuildContext context) =>
    _isDarkClubTheme(context) ? const Color(0x0EFFFFFF) : AppColors.card;

Color _clubPageBorder(BuildContext context) =>
    _isDarkClubTheme(context) ? const Color(0x14FFFFFF) : AppColors.divider;

Color _clubPageStrongBorder(BuildContext context) => _isDarkClubTheme(context)
    ? const Color(0x2EFFFFFF)
    : AppColors.divider.withValues(alpha: 0.95);

Color _clubPageBodyText(BuildContext context) => _isDarkClubTheme(context)
    ? const Color(0xD1FFFFFF)
    : AppColors.text.withValues(alpha: 0.82);

void _showClubRoleError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.couldNotUpdateBoardRole),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class ClubProfileScreen extends StatefulWidget {
  final Club club;
  final Color color;
  final int initialTabIndex;
  // When provided, the nav bar shows a settings gear instead of the back
  // button — used when this screen IS the logged-in club's Profile tab root.
  final VoidCallback? onSettings;

  const ClubProfileScreen({
    super.key,
    required this.club,
    required this.color,
    this.onSettings,
    this.initialTabIndex = 0,
  }) : assert(initialTabIndex >= 0 && initialTabIndex < 3);

  @override
  State<ClubProfileScreen> createState() => _ClubProfileScreenState();
}

class _ClubProfileScreenState extends State<ClubProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Mirrors [_tabController]'s index so the design frame's segmented pill can
  /// repaint on a swipe as well as a tap.
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
      vsync: this,
    );
    _tabIndex = widget.initialTabIndex;
    _tabController.addListener(_syncTabIndex);
  }

  void _syncTabIndex() {
    if (!mounted || _tabController.index == _tabIndex) return;
    setState(() => _tabIndex = _tabController.index);
  }

  /// The CLUB PROFİLE frames are the club's own point of view, so they run for
  /// a club-admin login and for a student switched to their club account —
  /// the same pair CLUB HOME and CLUB CHATS branch on. A student browsing a
  /// club, and the ClubUp platform moderator, keep the previous screen.
  bool get _isClubSession {
    if (accountSwitcherService.isClubAccountActive) return true;
    final admin = authService.currentAdmin;
    return admin != null && !isClubUpAdmin(admin);
  }

  /// A student browsing a club. `club-profile` `337:8` / `337:98` is the only
  /// club-profile design in the handoff — there is no student-POV frame — so
  /// students render the same chrome, with every admin control off (Insights
  /// needs [isCurrentAdminForClub], the gear needs `onSettings`, the post ⋯
  /// and the event/board long presses need `isAdmin`) and Follow + Club Chat
  /// in their place. The ClubUp platform moderator still gets the old screen.
  bool get _isStudentViewer => authService.isStudentSession && !_isClubSession;

  @override
  void dispose() {
    _tabController.removeListener(_syncTabIndex);
    _tabController.dispose();
    super.dispose();
  }

  // Posts by this club
  List get _clubPosts =>
      newsPosts
          .where((p) => p.clubId == widget.club.id && canViewPost(p))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // Events by this club
  List<Event> get _clubEvents =>
      events
          .where((e) => e.clubId == widget.club.id && canViewEvent(e))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  /// True when the currently logged-in admin is the admin of THIS club.
  bool get _isThisClubAdmin {
    final admin = authService.currentAdmin;
    if (admin == null) return false;
    return clubIsManagedByAdmin(widget.club, admin.id);
  }

  void _openCommunityChat() {
    final threadId = ChatStore.clubThreadId(widget.club.id);
    Navigator.of(context, rootNavigator: true).push(
      ChatPageRoute(
        settings: RouteSettings(
          name: '/clubs/${widget.club.id}/community',
          arguments: threadId,
        ),
        builder: (_) => ChatThreadScreen(threadId: threadId),
      ),
    );
  }

  List<User> get _membersForThisClub {
    final byId = <String, User>{
      for (final member in clubMembers(widget.club.id)) member.id: member,
      for (final member in peopleService.cachedPeople)
        if (member.subscribedClubIds.contains(widget.club.id))
          member.id: member,
    };
    final currentUser = authService.currentUser;
    if (currentUser != null && userState.isFollowing(widget.club.id)) {
      byId[currentUser.id] = currentUser;
    }
    final members = byId.values.toList();
    members.sort((a, b) {
      final aBoard = widget.club.boardMemberIds.contains(a.id);
      final bBoard = widget.club.boardMemberIds.contains(b.id);
      if (aBoard != bBoard) return aBoard ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return members;
  }

  void _openMembersDirectory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClubProfileMembersScreen(
          club: widget.club,
          initialMembers: _membersForThisClub,
        ),
      ),
    );
  }

  Future<void> _blockClub() async {
    final reason = await showModerationReasonSheet(
      context,
      title: S.whyBlockClub,
    );
    if (reason == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          S.blockClubQuestion(widget.club.name),
          style: TextStyle(color: AppColors.text),
        ),
        content: Text(
          S.blockUserExplanation,
          style: TextStyle(color: AppColors.secondaryText, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.blockAndReportClub),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    userState.followedClubIds.remove(widget.club.id);
    final myId = authService.currentUser?.id ?? '';
    await userPrefsService.save(myId);

    var delivered = true;
    try {
      await moderationService.blockClub(widget.club.id, reason: reason);
    } catch (_) {
      delivered = false;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.maybePop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            delivered ? S.clubBlockedAndReported : S.clubBlockedOffline,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _monthAbbr(int m) {
    return AppLocalizations.of(context)!.monthAbbr(m.toString());
  }

  List<String> _categoryTagsFor(Club club) {
    final raw = club.categoryName?.trim();
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  void _openInsights() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ClubInsightsScreen(club: widget.club, accent: widget.color),
    ),
  );

  /// Follow / Following + Club Chat, the pair the legacy student header
  /// carried. [ClubFollowButton] is shared with Explore, the feed and the
  /// event detail, so this is a local button on [ClubProfileColors] driving the
  /// same [handleFollowTap]. The card sits inside a `userState`
  /// [ListenableBuilder], so the label flips without extra plumbing.
  Widget _buildStudentActions() {
    final l10n = AppLocalizations.of(context)!;
    final isFollowing = userState.isFollowing(widget.club.id);
    return Row(
      children: [
        Expanded(
          child: ClubProfileActionButton(
            key: const ValueKey('club-profile-follow'),
            label: isFollowing ? l10n.following : l10n.follow,
            filled: !isFollowing,
            onTap: () => handleFollowTap(context, widget.club.id, () {
              if (mounted) setState(() {});
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClubProfileActionButton(
            key: const ValueKey('club-profile-club-chat'),
            label: S.clubChat,
            filled: false,
            icon: Icons.forum_outlined,
            onTap: _openCommunityChat,
          ),
        ),
      ],
    );
  }

  /// Long press on the identity card. Same presentation as
  /// [showClubBoardMemberActions] so the area has one action-sheet shape.
  Future<void> _showStudentClubActions() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: ClubProfileColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ClubProfileColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('club-profile-report'),
              leading: const Icon(
                Icons.flag_outlined,
                color: ClubProfileColors.danger,
              ),
              title: Text(
                S.blockAndReportClub,
                style: figtree(
                  size: 14,
                  weight: FontWeight.w600,
                  color: ClubProfileColors.danger,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) await _blockClub();
  }

  /// `club-profile` / `events` / `board` — Figma `337:8`, `343:12`,
  /// `332:1963`. One scroll: the header bar pins, the identity card, stat
  /// cells and segmented tabs scroll away above the selected stream.
  ///
  /// The old Club Chat shortcut stays in the Chats tab. Members and the board
  /// list open as full searchable pages from their profile entry points.
  Widget _buildDesignProfile({
    required List<dynamic> clubPosts,
    required List<Event> clubEvents,
    required int memberCount,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isOwner = isCurrentAdminForClub(widget.club);

    return Scaffold(
      backgroundColor: ClubProfileColors.page,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 60,
            backgroundColor: ClubProfileColors.page,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              bottom: false,
              child: ClubProfileHeaderBar(
                title: S.clubProfileTitle,
                onBack: Navigator.canPop(context)
                    ? () => Navigator.pop(context)
                    : null,
                actions: [
                  if (isOwner)
                    ClubProfileCircleButton(
                      key: const ValueKey('club-profile-insights'),
                      icon: Icons.bar_chart_rounded,
                      semanticLabel: S.clubInsightsTitle,
                      onTap: _openInsights,
                    ),
                  if (widget.onSettings != null)
                    ClubProfileCircleButton(
                      // Same singleton guard as the legacy header: only the
                      // logged-in club's own Profile tab root may own the
                      // onboarding anchor's GlobalKey.
                      key: onboardingAnchors.keyFor(
                        OnboardingAnchors.clubProfileSettings,
                      ),
                      icon: Icons.settings_outlined,
                      semanticLabel: l10n.settings,
                      onTap: () => widget.onSettings!(),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: userState,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  kClubProfileGutter,
                  8,
                  kClubProfileGutter,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      // The frame draws no overflow, so Report & Block — a
                      // student's only moderation route on this screen — hangs
                      // off a long press, as this area's board rows and event
                      // cards already do for controls the frames omit.
                      onLongPress: _isStudentViewer
                          ? _showStudentClubActions
                          : null,
                      child: ClubProfileIdentityCard(
                        avatar: ClubAvatar(
                          clubId: widget.club.id,
                          clubName: widget.club.name,
                          color: widget.color,
                          imageUrl: widget.club.logoUrl,
                          size: 60,
                          fontSize: 24,
                          borderRadius: 999,
                        ),
                        name: widget.club.name,
                        // Recalculate inside the UserState listener so an
                        // initials edit made in Settings updates this visible
                        // @handle without reopening the profile screen.
                        handle: clubHandle(widget.club),
                        description: widget.club.description,
                        categories: _categoryTagsFor(widget.club),
                        actions: _isStudentViewer
                            ? _buildStudentActions()
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClubProfileStatsRow(
                      cells: [
                        ClubProfileStat(
                          value: '${clubPosts.length}',
                          label: S.clubProfileTimeline,
                        ),
                        ClubProfileStat(
                          value: '$memberCount',
                          label: l10n.members,
                          onTap: _openMembersDirectory,
                        ),
                        ClubProfileStat(
                          value: '${clubEvents.length}',
                          label: l10n.events,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClubProfileSegmentedTabs(
                      key: widget.onSettings != null
                          ? onboardingAnchors.keyFor(
                              OnboardingAnchors.clubProfileTabs,
                            )
                          : null,
                      labels: [S.clubProfileTimeline, l10n.events, l10n.board],
                      index: _tabIndex,
                      onChanged: (i) {
                        if (_tabController.index == i) return;
                        _tabController.animateTo(i);
                        setState(() => _tabIndex = i);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _PostsTab(
              posts: clubPosts,
              club: widget.club,
              clubColor: widget.color,
              isAdmin: _isThisClubAdmin,
              designed: true,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            _EventsTab(
              clubId: widget.club.id,
              events: clubEvents,
              monthAbbr: _monthAbbr,
              clubColor: widget.color,
              isAdmin: _isThisClubAdmin,
              designed: true,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            _BoardTab(
              club: widget.club,
              designed: true,
              onBoardChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = clubMemberCount(widget.club.id);
    // Each getter filters+sorts a global list; capture once per build instead
    // of evaluating twice (stat cells + tab views). No UserState mutation can
    // change posts/events, so the captured values can't go stale within a
    // build (same reasoning as the memberCount local above).
    final clubPosts = _clubPosts;
    final clubEvents = _clubEvents;
    final bg = AppColors.background;
    final borderColor = _clubPageBorder(context);
    final subText = AppColors.secondaryText;
    final panelText = AppColors.text;
    final bodyText = _clubPageBodyText(context);
    final handle = clubHandle(widget.club);
    if (_isClubSession || _isStudentViewer) {
      return _buildDesignProfile(
        clubPosts: clubPosts,
        clubEvents: clubEvents,
        memberCount: memberCount,
      );
    }
    final showFollowAction = authService.isStudentSession && !_isThisClubAdmin;
    return Scaffold(
      backgroundColor: bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          // ── Nav bar ──
          SliverAppBar(
            pinned: true,
            toolbarHeight: 44,
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: panelText,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  )
                : const SizedBox(width: 40),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClubVerifiedName(
                  name: '@$handle',
                  badgeSize: 14,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: panelText,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)!.officialClubLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              // Owner's Profile tab: insights + a single settings gear.
              // Board management now lives inside Settings.
              if (isCurrentAdminForClub(widget.club))
                IconButton(
                  icon: Icon(
                    Icons.insights_rounded,
                    color: panelText,
                    size: 22,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClubInsightsScreen(
                        club: widget.club,
                        accent: widget.color,
                      ),
                    ),
                  ),
                ),
              if (widget.onSettings != null)
                IconButton(
                  // Only the logged-in club's own Profile tab root is a
                  // singleton — other visits to this screen (e.g. via search)
                  // must not share the same GlobalKey.
                  key: onboardingAnchors.keyFor(
                    OnboardingAnchors.clubProfileSettings,
                  ),
                  icon: Icon(
                    Icons.settings_outlined,
                    color: panelText,
                    size: 22,
                  ),
                  onPressed: () => widget.onSettings!(),
                ),
              if (showFollowAction)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: panelText,
                    size: 22,
                  ),
                  color: AppColors.card,
                  onSelected: (value) {
                    if (value == 'block') _blockClub();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.block_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            S.blockAndReportClub,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Scrollable header ──
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: userState,
              builder: (context, _) {
                final categoryTags = _categoryTagsFor(widget.club);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topCenter,
                          radius: 1.4,
                          colors: [
                            widget.color.withValues(alpha: 0.10),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.68],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar + Stats row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(28),
                                  ),
                                  gradient: LinearGradient(
                                    begin: const Alignment(-0.8, -0.8),
                                    end: const Alignment(0.8, 0.8),
                                    colors: [
                                      widget.color.withValues(alpha: 0.23),
                                      widget.color.withValues(alpha: 0.44),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: widget.color.withValues(alpha: 0.40),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.color.withValues(
                                        alpha: 0.10,
                                      ),
                                      blurRadius: 0,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(26),
                                  ),
                                  child: ClubAvatar(
                                    clubId: widget.club.id,
                                    clubName: widget.club.name,
                                    color: widget.color,
                                    imageUrl: widget.club.logoUrl,
                                    size: 104,
                                    fontSize: 46,
                                    borderRadius: 28,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _StatCell(
                                      value: '${clubPosts.length}',
                                      label: AppLocalizations.of(
                                        context,
                                      )!.posts,
                                      dark: true,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 28,
                                      color: borderColor,
                                    ),
                                    _StatCell(
                                      value: '$memberCount',
                                      label: AppLocalizations.of(
                                        context,
                                      )!.members,
                                      dark: true,
                                      onTap: _openMembersDirectory,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 28,
                                      color: borderColor,
                                    ),
                                    _StatCell(
                                      value: '${clubEvents.length}',
                                      label: AppLocalizations.of(
                                        context,
                                      )!.events,
                                      dark: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Name
                          Text(
                            widget.club.name,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: panelText,
                              letterSpacing: -0.5,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Badges
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(999),
                                  ),
                                ),
                                child: Text(
                                  '@$handle',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: widget.color,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              for (final category in categoryTags)
                                Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryRed.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(999),
                                      ),
                                    ),
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryRed,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Bio
                          Text(
                            widget.club.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: bodyText,
                              height: 1.6,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Every club has a members-only group chat
                          // (membership == following). Students see Follow +
                          // a Chat button that always opens the community;
                          // the thread itself gates history/input until joined.
                          if (showFollowAction) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: ClubFollowButton(
                                      clubId: widget.club.id,
                                      size: 'large',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _ClubChatButton(
                                  club: widget.club,
                                  onPressed: _openCommunityChat,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ] else if (_isThisClubAdmin) ...[
                            SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                key: ValueKey(
                                  'club-community-button-${widget.club.id}',
                                ),
                                onPressed: _openCommunityChat,
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                ),
                                label: Text(S.clubChat),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryRed,
                                  side: BorderSide(color: AppColors.primaryRed),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else
                            const SizedBox(height: 4),
                        ],
                      ),
                    ),

                    // Section divider
                    Container(height: 1, color: borderColor),
                  ],
                );
              },
            ),
          ),

          // ── Sticky tab bar ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              TabBar(
                // Same singleton guard as the insights/settings icons above.
                key: widget.onSettings != null
                    ? onboardingAnchors.keyFor(
                        OnboardingAnchors.clubProfileTabs,
                      )
                    : null,
                controller: _tabController,
                labelColor: AppColors.primaryRed,
                unselectedLabelColor: subText,
                indicatorColor: AppColors.primaryRed,
                indicatorSize: TabBarIndicatorSize.tab,
                labelPadding: EdgeInsets.zero,
                tabs: [
                  _IconTab(
                    icon: Icons.view_agenda_outlined,
                    label: S.clubProfileTimeline.toUpperCase(),
                  ),
                  _IconTab(
                    icon: Icons.event_rounded,
                    label: AppLocalizations.of(context)!.events.toUpperCase(),
                  ),
                  _IconTab(
                    icon: Icons.assignment_outlined,
                    label: AppLocalizations.of(context)!.board.toUpperCase(),
                  ),
                ],
              ),
              backgroundColor: AppColors.card,
              borderColor: borderColor,
              height: 58,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _PostsTab(
              posts: clubPosts,
              club: widget.club,
              clubColor: widget.color,
              isAdmin: _isThisClubAdmin,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            _EventsTab(
              clubId: widget.club.id,
              events: clubEvents,
              monthAbbr: _monthAbbr,
              clubColor: widget.color,
              isAdmin: _isThisClubAdmin,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            _BoardTab(
              club: widget.club,
              onBoardChanged: () {
                if (!mounted) return;
                // Refresh the header stats but stay on the BOARD tab so editing
                // a member's role doesn't bounce the admin back to Posts.
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Posts Tab ────────────────────────────────────────────────────────────────

class _PostsTab extends StatelessWidget {
  final List posts;
  final Club club;
  final Color clubColor;
  final bool isAdmin;
  final VoidCallback onChanged;

  /// CLUB PROFİLE chrome. Posts use a full-width timeline with the newest
  /// post first, matching the reading flow of the Home feed.
  final bool designed;

  const _PostsTab({
    required this.posts,
    required this.club,
    required this.clubColor,
    required this.isAdmin,
    required this.onChanged,
    this.designed = false,
  });

  Widget _buildDesigned(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ordered = [...posts]
      ..sort(
        (a, b) => (b.createdAt as DateTime).compareTo(a.createdAt as DateTime),
      );
    if (ordered.isEmpty) {
      return ListView(
        children: [
          ClubProfileEmptyState(
            icon: Icons.article_outlined,
            title: l10n.noPostsYet,
            message: l10n.whenClubPostsHint(club.name),
          ),
        ],
      );
    }
    return ListView.builder(
      key: const ValueKey('club-profile-posts'),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: ordered.length,
      itemBuilder: (context, i) => _ClubPostCompact(
        post: ordered[i],
        club: club,
        clubColor: clubColor,
        isAdmin: isAdmin,
        designed: true,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (designed) return _buildDesigned(context);
    if (posts.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
            child: Column(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 46,
                  color: AppColors.secondaryText.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.noPostsYet,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.whenClubPostsHint(club.name),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Club feed split into NEW THIS WEEK (pinned first, then last 7 days) and
    // EARLIER. Rebuilds on pin / like changes.
    return ListenableBuilder(
      listenable: userState,
      builder: (context, _) {
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final pinned = posts
            .where((p) => userState.isPostPinned(p.id as String))
            .toList();
        final pinnedIds = pinned.map((p) => p.id as String).toSet();
        final fresh = posts
            .where(
              (p) =>
                  !pinnedIds.contains(p.id) &&
                  (p.createdAt as DateTime).isAfter(weekAgo),
            )
            .toList();
        final earlier = posts
            .where(
              (p) =>
                  !pinnedIds.contains(p.id) &&
                  !(p.createdAt as DateTime).isAfter(weekAgo),
            )
            .toList();
        final newThisWeek = [...pinned, ...fresh];

        // Mix of section-label strings and post objects, built lazily below
        // instead of eagerly materializing every row up front.
        final items = <dynamic>[];
        if (newThisWeek.isNotEmpty) {
          items.add(AppLocalizations.of(context)!.newThisWeek);
          items.addAll(newThisWeek);
        }
        if (earlier.isNotEmpty) {
          items.add(AppLocalizations.of(context)!.earlier.toUpperCase());
          items.addAll(earlier);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is String) return _FeedLabel(item);
            return _ClubPostCompact(
              post: item,
              club: club,
              clubColor: clubColor,
              isAdmin: isAdmin,
              onChanged: onChanged,
            );
          },
        );
      },
    );
  }
}

/// Small letter-spaced section label with a trailing hairline (NEW / EARLIER).
class _FeedLabel extends StatelessWidget {
  final String text;
  const _FeedLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Container(height: 1, color: AppColors.divider)),
        ],
      ),
    );
  }
}

// ─── Club post card (compact) ─────────────────────────────────────────────────

/// Post row for the club profile. The redesigned profile uses a full timeline
/// card; the student-facing legacy profile keeps its compact list treatment.
class _ClubPostCompact extends StatelessWidget {
  final dynamic post;
  final Club club;
  final Color clubColor;
  final bool isAdmin;
  final VoidCallback onChanged;

  final bool designed;

  const _ClubPostCompact({
    required this.post,
    required this.club,
    required this.clubColor,
    required this.isAdmin,
    required this.onChanged,
    this.designed = false,
  });

  String _timeAgo(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    final loc = AppLocalizations.of(context)!;
    if (diff.inMinutes < 1) return loc.justNowShort;
    if (diff.inMinutes < 60) return loc.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return loc.hoursAgo(diff.inHours);
    if (diff.inDays < 7) {
      return loc.daysAgoLong(diff.inDays);
    }
    return loc.weeksAgo((diff.inDays / 7).floor());
  }

  void _openDetail(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PostDetailScreen(post: post, clubColor: clubColor),
    ),
  );

  void _togglePin() {
    userState.togglePinnedPost(post.id as String);
    userPrefsService.savePinnedPosts();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: Text(
          AppLocalizations.of(context)!.deletePost,
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        content: Text(
          AppLocalizations.of(context)!.deletePostFromClubMsg,
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final uid = authService.currentAdmin?.id ?? '';
    final typedPost = post is NewsPost ? post as NewsPost : null;
    if (typedPost == null) return;
    try {
      await supabasePostService.deletePost(typedPost);
      contentStore.deletePost(typedPost.id, uid);
      onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.couldNotDeletePostSupabase,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// The redesigned club profile uses the exact Home feed card so typography,
  /// media sizing, captions, polls and interaction rows cannot drift apart.
  Widget _buildDesigned(BuildContext context) {
    final postId = post.id as String;
    final typedPost = post as NewsPost;

    return ListenableBuilder(
      listenable: userState,
      builder: (context, _) {
        final pinned = userState.isPostPinned(postId);
        return HomeFeedPostCard(
          key: ValueKey('club-profile-post-$postId'),
          post: typedPost,
          clubContext: true,
          onChanged: onChanged,
          onTap: () => _openDetail(context),
          headerTrailing: isAdmin ? _designMenu(context, pinned) : null,
        );
      },
    );
  }

  Widget _designMenu(BuildContext context, bool pinned) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      key: ValueKey('club-profile-post-menu-${post.id}'),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180),
      iconSize: 18,
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: ClubProfileColors.muted,
      ),
      color: ClubProfileColors.card,
      onSelected: (v) {
        if (v == 'pin') _togglePin();
        if (v == 'delete') _confirmDelete(context);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(
            pinned ? l10n.unpinFromTop : l10n.pinToTop,
            style: figtree(
              size: 14,
              weight: FontWeight.w600,
              color: ClubProfileColors.text,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            l10n.deletePostMenuItem,
            style: figtree(
              size: 14,
              weight: FontWeight.w600,
              color: const Color(0xFFDC2626),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (designed) return _buildDesigned(context);
    final postId = post.id as String;
    final content = (post.content as String).trim();
    final hasImage =
        post.imagePath != null && (post.imagePath as String).isNotEmpty;

    return ListenableBuilder(
      listenable: userState,
      builder: (context, _) {
        final pinned = userState.isPostPinned(postId);
        final likeCount = postLikeCount(postId);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(context),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.7),
                  width: 0.6,
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, isAdmin ? 4 : 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail / accent tile
                ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: hasImage
                        ? buildPostBanner(
                            imagePath: post.imagePath as String?,
                            fallbackColor: clubColor,
                            fallbackLetter: club.name.isNotEmpty
                                ? club.name[0]
                                : '?',
                            height: 52,
                          )
                        : ClubAvatar(
                            clubId: club.id,
                            clubName: club.name,
                            color: clubColor,
                            imageUrl: club.logoUrl,
                            size: 52,
                            fontSize: 22,
                            borderRadius: 11,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (pinned) ...[
                            Icon(
                              Icons.push_pin_rounded,
                              size: 12,
                              color: AppColors.primaryRed,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _timeAgo(context, post.createdAt as DateTime),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: pinned
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: pinned
                                  ? AppColors.primaryRed
                                  : AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.text.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 14,
                            color: AppColors.secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$likeCount',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.secondaryText,
                      size: 20,
                    ),
                    color: AppColors.card,
                    onSelected: (v) {
                      if (v == 'pin') _togglePin();
                      if (v == 'delete') _confirmDelete(context);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              pinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin_rounded,
                              size: 19,
                              color: AppColors.text,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              pinned
                                  ? AppLocalizations.of(context)!.unpinFromTop
                                  : AppLocalizations.of(context)!.pinToTop,
                              style: TextStyle(color: AppColors.text),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context)!.deletePostMenuItem,
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Events Tab ───────────────────────────────────────────────────────────────

class _EventsTab extends StatefulWidget {
  final String clubId;
  final List<Event> events;
  final String Function(int) monthAbbr;
  final Color clubColor;
  final bool isAdmin;
  final VoidCallback onChanged;

  /// CLUB PROFİLE chrome.
  final bool designed;

  const _EventsTab({
    required this.clubId,
    required this.events,
    required this.monthAbbr,
    required this.clubColor,
    required this.isAdmin,
    required this.onChanged,
    this.designed = false,
  });

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  // 'past' | 'upcoming' — Club Profiles always open on Upcoming.
  String _filter = 'upcoming';
  List<Event> _loadedPastEvents = const [];
  bool _pastLoaded = false;
  bool _loadingPast = false;

  String _statusOf(Event event, [DateTime? at]) {
    final now = at ?? DateTime.now();
    final start = event.dateTime;
    final end = event.endTime;
    if (!end.isAfter(now)) return 'past';
    if (!start.isAfter(now)) return 'now'; // started, not yet ended → live
    return 'upcoming';
  }

  List<Event> _shownEvents(DateTime now) {
    final source = _filter == 'past' && _pastLoaded
        ? _loadedPastEvents
        : widget.events;
    final list = source.where((event) {
      final status = _statusOf(event, now);
      return _filter == 'past' ? status == 'past' : status != 'past';
    }).toList();
    list.sort(
      _filter == 'past'
          ? (a, b) => b.dateTime.compareTo(a.dateTime)
          : (a, b) => a.dateTime.compareTo(b.dateTime),
    );
    return list;
  }

  void _selectFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    if (filter == 'past') {
      // Re-entering Past retries a transient/offline fetch while keeping the
      // last successful history cached between filter switches.
      unawaited(_loadPastEvents(force: _pastLoaded));
    }
  }

  Future<void> _loadPastEvents({bool force = false}) async {
    if (_loadingPast || (_pastLoaded && !force)) return;
    setState(() => _loadingPast = true);
    final fetched = await supabaseContentService.fetchPastEventsForClub(
      widget.clubId,
    );
    if (!mounted) return;
    setState(() {
      // This is a targeted query, so it never passes through _clubEvents and
      // needs the audience filter applied on its own.
      _loadedPastEvents = fetched.where(canViewEvent).toList();
      _pastLoaded = true;
      _loadingPast = false;
    });
    // The targeted query is merged into the shared event cache, so update the
    // Club Profile's event count without moving away from this filter.
    widget.onChanged();
  }

  void _handleEventChanged() {
    widget.onChanged();
    if (_filter == 'past') unawaited(_loadPastEvents(force: true));
  }

  @override
  void didUpdateWidget(covariant _EventsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clubId != widget.clubId) {
      _filter = 'upcoming';
      _loadedPastEvents = const [];
      _pastLoaded = false;
      _loadingPast = false;
    }
  }

  /// `events` `343:12`. The frame draws no filter, but the club's own history
  /// is only reachable through one — `fetchPastEventsForClub` has no other
  /// entry point — so the Upcoming / Past switch stays, in the frame's own
  /// segmented language.
  Widget _buildDesigned(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final shown = _shownEvents(now);
    final segments = ['upcoming', 'past'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kClubProfileGutter,
            0,
            kClubProfileGutter,
            12,
          ),
          child: ClubProfileSegmentedTabs(
            keyPrefix: 'club-events-filter',
            compact: true,
            labels: [loc.upcomingSegmentLabel, loc.past],
            index: segments.indexOf(_filter),
            onChanged: (i) => _selectFilter(segments[i]),
          ),
        ),
        Expanded(
          child: _filter == 'past' && _loadingPast && !_pastLoaded
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
              ? ListView(
                  children: [
                    ClubProfileEmptyState(
                      icon: Icons.event_outlined,
                      title: _filter == 'past'
                          ? loc.noPastEventsYet
                          : loc.nothingHereRightNow,
                      message: _filter == 'past'
                          ? null
                          : loc.checkBackSoonEvents,
                    ),
                  ],
                )
              : ListView.separated(
                  key: const ValueKey('club-profile-events'),
                  padding: const EdgeInsets.fromLTRB(
                    kClubProfileGutter,
                    0,
                    kClubProfileGutter,
                    96,
                  ),
                  itemCount: shown.length + (widget.isAdmin ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == shown.length) {
                      return Text(
                        S.clubProfileEventHint,
                        style: figtree(
                          size: 12,
                          weight: FontWeight.w400,
                          color: ClubProfileColors.muted,
                          height: 1.4,
                        ),
                      );
                    }
                    return _EventCardV2(
                      event: shown[i],
                      status: _statusOf(shown[i], now),
                      monthAbbr: widget.monthAbbr,
                      clubColor: widget.clubColor,
                      isAdmin: widget.isAdmin,
                      designed: true,
                      onChanged: _handleEventChanged,
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.designed) return _buildDesigned(context);
    final loc = AppLocalizations.of(context)!;
    final segments = [
      ('upcoming', loc.upcomingSegmentLabel),
      ('past', loc.past),
    ];
    final now = DateTime.now();
    final shown = _shownEvents(now);
    final panelColor = _clubPagePanel(context);

    return Column(
      children: [
        // The Club Profile's one event area switches in place between its
        // upcoming/live events and completed history.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.all(Radius.circular(11)),
            ),
            child: Row(
              children: segments.map((seg) {
                final active = _filter == seg.$1;
                final countSource = seg.$1 == 'past' && _pastLoaded
                    ? _loadedPastEvents
                    : widget.events;
                final n = countSource.where((event) {
                  final status = _statusOf(event, now);
                  return seg.$1 == 'past' ? status == 'past' : status != 'past';
                }).length;
                return Expanded(
                  child: GestureDetector(
                    key: ValueKey('club-events-filter-${seg.$1}'),
                    onTap: () => _selectFilter(seg.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primaryRed
                            : Colors.transparent,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            seg.$2,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.white
                                  : AppColors.secondaryText,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : AppColors.secondaryText.withValues(
                                      alpha: 0.6,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Cards / empty state.
        Expanded(
          child: _filter == 'past' && _loadingPast && !_pastLoaded
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 44,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          Text(
                            _filter == 'past'
                                ? loc.noPastEventsYet
                                : loc.nothingHereRightNow,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          if (_filter != 'past') ...[
                            const SizedBox(height: 4),
                            Text(
                              loc.checkBackSoonEvents,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _EventCardV2(
                    event: shown[i],
                    status: _statusOf(shown[i], now),
                    monthAbbr: widget.monthAbbr,
                    clubColor: widget.clubColor,
                    isAdmin: widget.isAdmin,
                    onChanged: _handleEventChanged,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Event card with a status pill (HAPPENING NOW · UPCOMING · PAST), date badge,
/// time / location / attendance rows, and a contextual action (Join / RSVP /
/// Recap). Live events get a green accent and a pulsing dot; past events dim.
class _EventCardV2 extends StatelessWidget {
  final dynamic event;
  final String status; // 'past' | 'now' | 'upcoming'
  final String Function(int) monthAbbr;
  final Color clubColor;

  final bool isAdmin;
  final VoidCallback onChanged;

  /// CLUB PROFİLE chrome.
  final bool designed;

  const _EventCardV2({
    required this.event,
    required this.status,
    required this.monthAbbr,
    required this.clubColor,
    this.isAdmin = false,
    this.designed = false,
    this.onChanged = _noop,
  });

  static void _noop() {}

  static const Color _green = Color(0xFF2E9E5B);

  // Applies the same dimming an outer Opacity(opacity: dim) would, without
  // the offscreen saveLayer that wrapping the whole card in Opacity forces.
  static Color _dim(Color c, double dim) =>
      dim == 1.0 ? c : c.withValues(alpha: c.a * dim);

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: Text(
          AppLocalizations.of(context)!.deleteEvent,
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteEventFromClubMsg,
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final uid = authService.currentAdmin?.id ?? '';
    final typedEvent = event is Event ? event as Event : null;
    if (typedEvent == null) return;
    try {
      await supabaseEventService.deleteEvent(typedEvent);
      contentStore.deleteEvent(typedEvent.id, uid);
      onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.couldNotDeleteEventSupabase,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _openDetail(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          EventDetailScreen(event: event as dynamic, color: clubColor),
    ),
  );

  /// Compact horizontal event row aligned with the main Events tab. A club
  /// cannot RSVP to its own event, so the row and chevron open its details.
  Widget _buildDesigned(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final typed = event as Event;
    final isLive = status == 'now';
    final isPast = status == 'past';

    return ClubProfileEventCard(
      key: ValueKey('club-event-card-${event.id}'),
      cover: EventCoverImage(
        event: typed,
        color: clubColor,
        fit: BoxFit.cover,
        cacheWidth: 400,
      ),
      title: typed.title,
      dateLabel: DateFormat('EEE, d MMM', locale).format(typed.dateTime),
      timeLabel: _clock(typed.dateTime),
      location: typed.location,
      statusLabel: isLive
          ? loc.happeningNowLabel
          : isPast
          ? loc.past
          : null,
      // The club's own events list is where a board member checks who a
      // restricted event actually went out to.
      audienceBadge: audienceForEvent(typed) == ContentAudience.everyone
          ? null
          : ContentAudiencePill(
              key: ValueKey('content-audience-pill-${typed.id}'),
              audience: audienceForEvent(typed),
              accent: ClubProfileColors.accent,
              foreground: ClubProfileColors.accentText,
            ),
      // A club cannot RSVP its own event, so its label reads View / Recap.
      // A student's reads what the frame drew — the same three-way label the
      // legacy card used. The tap opens the event either way; the RSVP itself
      // lives on the detail screen.
      actionLabel: authService.isStudentSession
          ? (isLive
                ? loc.join
                : isPast
                ? loc.recapLabel
                : loc.rsvp)
          : (isPast ? loc.recapLabel : loc.viewLabel),
      onAction: () => _openDetail(context),
      onTap: () => _openDetail(context),
      onLongPress: isAdmin ? () => _confirmDelete(context) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (designed) return _buildDesigned(context);
    final isLive = status == 'now';
    final isPast = status == 'past';
    final accent = isLive ? _green : AppColors.primaryRed;
    final cardColor = _clubPageCard(context);
    final borderColor = _clubPageBorder(context);
    final strongBorder = _clubPageStrongBorder(context);
    final panelColor = _clubPagePanel(context);
    final dt = event.dateTime as DateTime;

    final loc = AppLocalizations.of(context)!;
    final timeLabel = isLive
        ? loc.todayAtTime(_clock(dt))
        : isPast
        ? '${monthAbbr(dt.month)} ${dt.day} · ${_clock(dt)}'
        : _clock(dt);
    // Same visual dimming a wrapping Opacity(opacity: dim) would give, but
    // applied per-color so the card avoids an offscreen saveLayer.
    final dim = isPast ? 0.82 : 1.0;

    return GestureDetector(
      key: ValueKey('club-event-card-${event.id}'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              EventDetailScreen(event: event as dynamic, color: clubColor),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dim(cardColor, dim),
          border: Border.all(
            color: _dim(
              isLive ? _green.withValues(alpha: 0.4) : borderColor,
              dim,
            ),
          ),
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date badge
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: _dim(panelColor, dim),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    monthAbbr(dt.month),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _dim(
                        isPast ? AppColors.secondaryText : accent,
                        dim,
                      ),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${dt.day}',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: _dim(AppColors.text, dim),
                      height: 1.1,
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
                  // Status pill
                  _statusPill(context, dim),
                  const SizedBox(height: 6),
                  Text(
                    event.title as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _dim(AppColors.text, dim),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow(Icons.access_time_rounded, timeLabel, dim),
                  const SizedBox(height: 4),
                  _infoRow(
                    Icons.location_on_outlined,
                    event.location as String,
                    dim,
                  ),
                  if (canViewEventAttendance(event)) ...[
                    const SizedBox(height: 4),
                    _infoRow(
                      Icons.people_outline,
                      isPast
                          ? loc.attendedCount(
                              (event.attendeeUserIds as List).length,
                            )
                          : isLive
                          ? loc.attendingCount(
                              (event.attendeeUserIds as List).length,
                            )
                          : loc.goingCount(
                              (event.attendeeUserIds as List).length,
                            ),
                      dim,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action (+ admin delete menu on the club's own profile)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin) ...[
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: _dim(AppColors.secondaryText, dim),
                      size: 20,
                    ),
                    color: AppColors.card,
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'delete') _confirmDelete(context);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context)!.deleteEventMenuItem,
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isPast ? Colors.transparent : _dim(accent, dim),
                    border: isPast
                        ? Border.all(color: _dim(strongBorder, dim))
                        : null,
                    borderRadius: BorderRadius.all(Radius.circular(9)),
                  ),
                  child: Text(
                    authService.isStudentSession
                        ? (isLive
                              ? loc.join
                              : isPast
                              ? loc.recapLabel
                              : loc.rsvp)
                        : (isPast ? loc.recapLabel : loc.viewLabel),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isPast ? _dim(AppColors.text, dim) : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context, double dim) {
    final loc = AppLocalizations.of(context)!;
    if (status == 'now') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: _dim(_green.withValues(alpha: 0.14), dim),
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LiveDot(color: _green),
            const SizedBox(width: 5),
            Text(
              loc.happeningNowLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: _dim(_green, dim),
              ),
            ),
          ],
        ),
      );
    }
    final isPast = status == 'past';
    final c = isPast ? AppColors.secondaryText : AppColors.primaryRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _dim(c.withValues(alpha: 0.14), dim),
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        isPast
            ? loc.past.toUpperCase()
            : loc.upcomingSegmentLabel.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: _dim(c, dim),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, double dim) {
    return Row(
      children: [
        Icon(icon, size: 11, color: _dim(AppColors.secondaryText, dim)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: _dim(AppColors.secondaryText, dim),
            ),
          ),
        ),
      ],
    );
  }

  String _clock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// A small pulsing dot for the HAPPENING NOW status pill.
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.78).animate(_c),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─── Sticky tab bar delegate ──────────────────────────────────────────────────

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;
  final double height;
  const _StickyTabBarDelegate(
    this.tabBar, {
    required this.backgroundColor,
    required this.borderColor,
    this.height = 0,
  });

  double get _h => height > 0 ? height : tabBar.preferredSize.height;

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 0.6),
          bottom: BorderSide(color: borderColor, width: 0.6),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          height: _h,
          child: Center(child: tabBar),
        ),
      ),
    );
  }

  @override
  // No tabBar term: a fresh (non-const) TabBar instance is built every parent
  // rebuild, so comparing instances made this always-true. The TabBar's config
  // is static per theme, and theme flips still rebuild via the color terms.
  bool shouldRebuild(_StickyTabBarDelegate old) =>
      old.backgroundColor != backgroundColor ||
      old.borderColor != borderColor ||
      old.height != height;
}

// ─── Board Management Sheet ───────────────────────────────────────────────────

class BoardManagementSheet extends StatefulWidget {
  final Club club;
  const BoardManagementSheet({super.key, required this.club});

  @override
  State<BoardManagementSheet> createState() => BoardManagementSheetState();
}

class BoardManagementSheetState extends State<BoardManagementSheet> {
  final _searchController = TextEditingController();
  List<User> _followers = const [];
  String _query = '';
  bool _loadingFollowers = false;
  String? _followersError;

  @override
  void initState() {
    super.initState();
    _followers = _sortUsers(clubMembers(widget.club.id));
    _loadFollowers();
  }

  List<User> get _availableFollowers {
    final q = _query.trim().toLowerCase();
    return _followers
        .where(
          (u) =>
              (q.isEmpty ||
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q)) &&
              !widget.club.boardMemberIds.contains(u.id),
        )
        .toList();
  }

  List<User> get _currentBoardMembers {
    final pool = <String, User>{
      for (final u in users) u.id: u,
      for (final u in peopleService.cachedPeople) u.id: u,
      for (final u in _followers) u.id: u,
    };
    return widget.club.boardMemberIds
        .map((id) => pool[id])
        .whereType<User>()
        .toList();
  }

  List<User> _sortUsers(List<User> source) {
    final sorted = [...source];
    sorted.sort((a, b) {
      final aBoard = widget.club.boardMemberIds.contains(a.id);
      final bBoard = widget.club.boardMemberIds.contains(b.id);
      if (aBoard != bBoard) return aBoard ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Future<void> _loadFollowers() async {
    setState(() {
      _loadingFollowers = true;
      _followersError = null;
    });

    try {
      final followers = await peopleService.fetchClubMembers(widget.club.id);
      if (!mounted) return;
      setState(() {
        if (followers.isNotEmpty || _followers.isEmpty) {
          _followers = _sortUsers(followers);
        }
        _loadingFollowers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFollowers = false;
        _followersError = _followers.isEmpty
            ? AppLocalizations.of(context)!.followersLoadError
            : null;
      });
    }
  }

  Future<void> _addMember(String userId) async {
    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: userId,
        isBoardMember: true,
      );
    } catch (_) {
      _showRoleError();
      return;
    }
    _searchController.clear();
    _query = '';
    if (!mounted) return;
    setState(() => _followers = _sortUsers(_followers));
  }

  Future<void> _editTitleInSheet(dynamic u) async {
    final current = widget.club.boardMemberTitles[u.id] ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _BoardTitleDialog(memberName: u.name, initialTitle: current),
    );
    if (result == null || !mounted) return;
    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: u.id,
        isBoardMember: result.trim().isNotEmpty,
        title: result,
      );
    } catch (_) {
      _showRoleError();
      return;
    }
    if (!mounted) return;
    setState(() => _followers = _sortUsers(_followers));
  }

  Future<void> _removeMember(dynamic u) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.of(context)!.removeBoardMemberTitle,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppLocalizations.of(context)!.confirmRemoveBoardMemberBody(u.name),
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.removeLabel,
              style: TextStyle(color: AppColors.primaryRed),
            ),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.of(context)!.confirmRemovalTitle,
          style: TextStyle(
            color: AppColors.primaryRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          AppLocalizations.of(
            context,
          )!.confirmRemovalBody(u.name, widget.club.name),
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.yesRemoveLabel),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: u.id,
        isBoardMember: false,
      );
    } catch (_) {
      _showRoleError();
      return;
    }
    if (!mounted) return;
    setState(() => _followers = _sortUsers(_followers));
  }

  void _showRoleError() {
    _showClubRoleError(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardMembers = _currentBoardMembers;
    final availableFollowers = _availableFollowers;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle + title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.manage_accounts_outlined,
                        color: AppColors.primaryRed,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.manageBoardMembers,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.boardMembersPublicHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Search field
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(fontSize: 14, color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(
                        context,
                      )!.searchFollowersHint,
                      hintStyle: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.secondaryText,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            Divider(height: 1),

            Expanded(
              child: _buildFollowersAndBoardList(
                scrollController,
                availableFollowers,
                boardMembers,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryText,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _followerTile(User u) => ListTile(
    leading: UserAvatar(
      userId: u.id,
      name: u.name,
      size: 40,
      fontSize: 16,
      backgroundColor: AppColors.lightRed,
      textColor: AppColors.primaryRed,
    ),
    title: Text(
      userState.displayNameFor(u.id, u.name),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    subtitle: Text(
      u.email,
      style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
    ),
    trailing: TextButton(
      onPressed: () => _addMember(u.id),
      style: TextButton.styleFrom(
        backgroundColor: AppColors.lightRed,
        foregroundColor: AppColors.primaryRed,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      child: Text(
        AppLocalizations.of(context)!.addLabel,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _boardMemberTile(User u) {
    final title = widget.club.boardMemberTitles[u.id];
    final hasTitle = title?.isNotEmpty == true;
    return ListTile(
      leading: UserAvatar(
        userId: u.id,
        name: u.name,
        size: 40,
        fontSize: 16,
        backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
        textColor: const Color(0xFF1565C0),
      ),
      title: Text(
        userState.displayNameFor(u.id, u.name),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasTitle
                ? localizedClubRole(AppLocalizations.of(context)!, title)
                : AppLocalizations.of(context)!.noTitleSet,
            style: TextStyle(
              fontSize: 12,
              color: hasTitle
                  ? const Color(0xFF1565C0)
                  : AppColors.secondaryText,
              fontWeight: hasTitle ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            u.email,
            style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: Color(0xFF1565C0), size: 20),
            tooltip: AppLocalizations.of(context)!.setTitleTooltip,
            onPressed: () => _editTitleInSheet(u),
          ),
          IconButton(
            icon: Icon(
              Icons.remove_circle_outline,
              color: AppColors.secondaryText,
              size: 22,
            ),
            tooltip: AppLocalizations.of(context)!.removeFromBoardLabel,
            onPressed: () => _removeMember(u),
          ),
        ],
      ),
    );
  }

  /// Mix of fixed chrome (loading indicator, headers/divider/empty state —
  /// cheap and few regardless of data size) and person rows, the latter
  /// built lazily instead of eagerly materializing every row up front.
  Widget _buildFollowersAndBoardList(
    ScrollController scrollController,
    List<User> availableFollowers,
    List<User> boardMembers,
  ) {
    final items = <Object>[];
    if (_loadingFollowers) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: LinearProgressIndicator(
            color: AppColors.primaryRed,
            minHeight: 2,
          ),
        ),
      );
    }
    if (availableFollowers.isNotEmpty) {
      items.add(
        _sectionHeader(
          AppLocalizations.of(
            context,
          )!.followersCountHeader(availableFollowers.length),
        ),
      );
      items.addAll(availableFollowers.map((u) => (user: u, isFollower: true)));
      items.add(const Divider(height: 16));
    }
    items.add(
      _sectionHeader(
        boardMembers.isEmpty
            ? AppLocalizations.of(context)!.noBoardMembers
            : AppLocalizations.of(
                context,
              )!.currentBoardMembersHeader(boardMembers.length),
      ),
    );
    if (boardMembers.isEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text(
            _followersError ??
                (_followers.isEmpty
                    ? AppLocalizations.of(context)!.noFollowersYet
                    : AppLocalizations.of(context)!.addFollowerAboveHint),
            style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
          ),
        ),
      );
    } else {
      items.addAll(boardMembers.map((u) => (user: u, isFollower: false)));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is Widget) return item;
        final row = item as ({User user, bool isFollower});
        return row.isFollower
            ? _followerTile(row.user)
            : _boardMemberTile(row.user);
      },
    );
  }
}

// ─── Board Tab ────────────────────────────────────────────────────────────────

class _BoardTab extends StatefulWidget {
  final Club club;
  final VoidCallback onBoardChanged;

  /// CLUB PROFİLE chrome.
  final bool designed;

  const _BoardTab({
    required this.club,
    required this.onBoardChanged,
    this.designed = false,
  });

  @override
  State<_BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<_BoardTab> {
  @override
  void initState() {
    super.initState();
    // Load the club's members into the people cache so board members whose
    // profiles aren't in the static seed data resolve and render immediately —
    // without the user having to open the Members sheet first.
    _ensureMembersLoaded();
  }

  Future<void> _ensureMembersLoaded() async {
    try {
      await peopleService.fetchClubMembers(widget.club.id);
    } catch (_) {
      // Offline / mock mode — board members come from the static user list.
    }
    if (mounted) setState(() {});
  }

  // Only the club's own admin can approve/decline requests, add/remove members,
  // or assign titles. Board members and external users have no write access.
  bool get _isClubAdmin {
    final adminId = authService.currentAdmin?.id ?? '';
    final userId = authService.currentUser?.id ?? '';
    return clubIsManagedByAdmin(widget.club, adminId) ||
        widget.club.adminUserIds.contains(userId);
  }

  Future<void> _editTitle(dynamic u) async {
    final current = widget.club.boardMemberTitles[u.id] ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _BoardTitleDialog(memberName: u.name, initialTitle: current),
    );
    if (result == null || !mounted) return;
    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: u.id,
        isBoardMember: result.trim().isNotEmpty,
        title: result,
      );
    } catch (_) {
      if (!mounted) return;
      _showClubRoleError(context);
      return;
    }
    if (!mounted) return;
    setState(() {});
    widget.onBoardChanged();
  }

  Future<void> _confirmRemove(dynamic u) async {
    // First confirmation
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.of(context)!.removeBoardMemberTitle,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppLocalizations.of(context)!.confirmRemoveBoardMemberBody(u.name),
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.removeLabel,
              style: TextStyle(color: AppColors.primaryRed),
            ),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    // Second confirmation
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.of(context)!.confirmRemovalTitle,
          style: TextStyle(
            color: AppColors.primaryRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          AppLocalizations.of(
            context,
          )!.confirmRemovalBody(u.name, widget.club.name),
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.yesRemoveLabel),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: u.id,
        isBoardMember: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showClubRoleError(context);
      return;
    }
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.removedFromBoard(u.name)),
        behavior: SnackBarBehavior.floating,
      ),
    );
    widget.onBoardChanged();
  }

  /// Every board-member id resolved against the static user list and the
  /// people-service cache, so a member added from the live members list still
  /// renders for everyone.
  List<User> get _resolvedMembers {
    final pool = <String, User>{
      for (final u in users) u.id: u,
      for (final u in peopleService.cachedPeople) u.id: u,
    };
    return widget.club.boardMemberIds
        .map((id) => pool[id])
        .whereType<User>()
        .toList();
  }

  String _roleFor(BuildContext context, User member) {
    final title = widget.club.boardMemberTitles[member.id]?.trim() ?? '';
    if (title.isEmpty) return AppLocalizations.of(context)!.boardMemberLabel;
    return localizedClubRole(AppLocalizations.of(context)!, title);
  }

  Future<void> _openAllMembers(List<User> members) async {
    final authorized = _isClubAdmin;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClubBoardMembersScreen(
          club: widget.club,
          members: members,
          onEditTitle: authorized ? _editTitle : null,
          onRemove: authorized ? _confirmRemove : null,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// `board` `332:1963` — "Board members" over plain rows. The frame draws no
  /// per-row control, so the club's edit-title / remove actions moved onto a
  /// long press.
  Widget _buildDesigned(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final members = _resolvedMembers;
    final authorized = _isClubAdmin;

    return ListView(
      key: const ValueKey('club-profile-board'),
      padding: const EdgeInsets.fromLTRB(
        kClubProfileGutter,
        0,
        kClubProfileGutter,
        96,
      ),
      children: [
        ClubProfileSectionHeader(
          title: l10n.boardMembers,
          actionLabel: members.isEmpty ? null : S.clubProfileViewAll,
          onAction: () => _openAllMembers(members),
        ),
        const SizedBox(height: 12),
        if (members.isEmpty)
          ClubProfileEmptyState(
            icon: Icons.shield_outlined,
            title: l10n.noBoardMembers,
            message: l10n.clubAdminsAddMembersHint,
          )
        else ...[
          for (final member in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClubProfileMemberRow(
                key: ValueKey('club-board-row-${member.id}'),
                avatar: UserAvatar(
                  userId: member.id,
                  name: member.name,
                  size: 44,
                  fontSize: 18,
                ),
                name: userState.displayNameFor(member.id, member.name),
                role: _roleFor(context, member),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(user: member),
                  ),
                ),
                onLongPress: authorized
                    ? () =>
                          showClubBoardMemberActions(
                            context: context,
                            onEditTitle: () => _editTitle(member),
                            onRemove: () => _confirmRemove(member),
                          ).then((_) {
                            if (mounted) setState(() {});
                          })
                    : null,
              ),
            ),
          if (authorized)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                S.clubProfileBoardHint,
                style: figtree(
                  size: 12,
                  weight: FontWeight.w400,
                  color: ClubProfileColors.muted,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.designed) return _buildDesigned(context);
    // Resolve every board-member id against both the static user list and the
    // people-service cache, so a member added from the live members list (not
    // in the seed data) still shows up here for everyone.
    final pool = <String, User>{
      for (final u in users) u.id: u,
      for (final u in peopleService.cachedPeople) u.id: u,
    };
    final members = widget.club.boardMemberIds
        .map((id) => pool[id])
        .whereType<User>()
        .toList();
    final authorized = _isClubAdmin;
    final cardColor = _clubPageCard(context);
    final borderColor = _clubPageBorder(context);
    final panelText = AppColors.text;
    final mutedText = AppColors.secondaryText;

    final headerRow = Container(
      width: double.infinity,
      color: cardColor,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF1565C0), size: 20),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.boardMembers,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: panelText,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x1E1565C0),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Text(
              '${members.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ),
    );

    Widget buildMemberRow(User u) {
      final title = widget.club.boardMemberTitles[u.id];
      final isAdmin = _isClubAdmin;
      return Column(
        children: [
          ListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => UserProfileScreen(user: u)),
            ),
            leading: UserAvatar(
              userId: u.id,
              name: u.name,
              size: 44,
              fontSize: 18,
              backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
              textColor: const Color(0xFF1565C0),
            ),
            title: Text(
              userState.displayNameFor(u.id, u.name),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: panelText,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.isNotEmpty)
                  Text(
                    localizedClubRole(AppLocalizations.of(context)!, title),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    AppLocalizations.of(context)!.boardMemberLabel,
                    style: TextStyle(fontSize: 12, color: mutedText),
                  ),
                Text(u.email, style: TextStyle(fontSize: 11, color: mutedText)),
              ],
            ),
            trailing: authorized
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Color(0xFF1565C0),
                            size: 20,
                          ),
                          tooltip: AppLocalizations.of(
                            context,
                          )!.setTitleTooltip,
                          onPressed: () => _editTitle(u),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: mutedText,
                          size: 22,
                        ),
                        tooltip: AppLocalizations.of(
                          context,
                        )!.removeFromBoardLabel,
                        onPressed: () => _confirmRemove(u),
                      ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1E1565C0),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.board,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
          ),
          Divider(height: 1, indent: 72, color: borderColor),
        ],
      );
    }

    final emptyState = Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 48, color: mutedText),
          SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.noBoardMembers,
            style: TextStyle(fontSize: 15, color: mutedText),
          ),
          SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)!.clubAdminsAddMembersHint,
            style: TextStyle(fontSize: 12, color: mutedText),
          ),
        ],
      ),
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: 2 + (members.isEmpty ? 1 : members.length),
      itemBuilder: (context, i) {
        if (i == 0) return headerRow;
        if (i == 1) return Divider(height: 1, color: borderColor);
        if (members.isEmpty) return emptyState;
        return buildMemberRow(members[i - 2]);
      },
    );
  }
}

// ─── Board title dialog ───────────────────────────────────────────────────────
// Owns its TextEditingController so it is disposed only when the dialog route is
// fully gone — avoids "TextEditingController used after being disposed" crashes
// that happen if the caller disposes the controller during the close animation.
// Pops with: null (cancel), '' (remove title), or the trimmed title (save).

class _BoardTitleDialog extends StatefulWidget {
  final String memberName;
  final String initialTitle;

  const _BoardTitleDialog({
    required this.memberName,
    required this.initialTitle,
  });

  @override
  State<_BoardTitleDialog> createState() => _BoardTitleDialogState();
}

class _BoardTitleDialogState extends State<_BoardTitleDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(
        AppLocalizations.of(context)!.setTitleForMember(widget.memberName),
        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        style: TextStyle(color: AppColors.text),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.presidentSecretaryHint,
          hintStyle: TextStyle(color: AppColors.secondaryText),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            AppLocalizations.of(context)!.cancel,
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        if (widget.initialTitle.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(
              AppLocalizations.of(context)!.removeRoleLabel,
              style: TextStyle(color: AppColors.primaryRed),
            ),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }
}

// ─── Stat cell ────────────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final bool dark;
  final VoidCallback? onTap;
  const _StatCell({
    required this.value,
    required this.label,
    this.dark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: dark
                ? AppColors.secondaryText.withValues(alpha: 0.9)
                : AppColors.secondaryText,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: content,
      ),
    );
  }
}

// ─── Members sheet ───────────────────────────────────────────────────────────

class _ClubMembersSheet extends StatefulWidget {
  final Club club;
  final Color color;
  final List<User> members;
  final int totalCount;

  const _ClubMembersSheet({
    required this.club,
    required this.color,
    required this.members,
    required this.totalCount,
  });

  @override
  State<_ClubMembersSheet> createState() => _ClubMembersSheetState();
}

class _ClubMembersSheetState extends State<_ClubMembersSheet> {
  late List<User> _members = widget.members;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final members = await peopleService.fetchClubMembers(widget.club.id);
      if (!mounted) return;
      setState(() {
        _members = _sortMembers(
          peopleService.reconcileCurrentClubMember(
            fetchedMembers: members,
            fallbackMembers: widget.members,
            currentUser: authService.currentUser,
            currentUserIsFollowing: userState.isFollowing(widget.club.id),
          ),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _members = _sortMembers(
          peopleService.reconcileCurrentClubMember(
            fetchedMembers: const [],
            fallbackMembers: widget.members,
            currentUser: authService.currentUser,
            currentUserIsFollowing: userState.isFollowing(widget.club.id),
          ),
        );
        _loading = false;
        _error = widget.members.isEmpty
            ? AppLocalizations.of(context)!.memberProfilesLoadError
            : null;
      });
    }
  }

  List<User> _sortMembers(List<User> members) {
    final sorted = [...members];
    sorted.sort((a, b) {
      final aBoard = widget.club.boardMemberIds.contains(a.id);
      final bBoard = widget.club.boardMemberIds.contains(b.id);
      if (aBoard != bBoard) return aBoard ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  /// Only the club's own admin can assign / clear board roles here.
  bool get _isClubAdmin =>
      clubIsManagedByAdmin(widget.club, authService.currentAdmin?.id ?? '');

  /// The role label for [member], or null if they hold no board role.
  String? _roleFor(User member) {
    return studentClubRoleService.roleTitleFor(widget.club, member.id);
  }

  void _viewProfile(User member) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfileScreen(user: member)),
    );
  }

  /// Removes [member] from the club and clears any board role first so a
  /// failed server role update never leaves local profile state out of sync.
  Future<void> _removeMember(User member) async {
    final hadRole = widget.club.boardMemberIds.contains(member.id);

    try {
      if (hadRole) {
        await studentClubRoleService.setBoardMembership(
          club: widget.club,
          userId: member.id,
          isBoardMember: false,
        );
      }
      await clubFollowService.unfollowClub(
        userId: member.id,
        clubId: widget.club.id,
      );
      peopleService.invalidateClubMembers(widget.club.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _members = _sortMembers(_members));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.couldNotRemoveClubMember),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _members = _members.where((m) => m.id != member.id).toList();
    });
    final cached = supabaseClubMemberCounts[widget.club.id];
    if (cached != null && cached > 0) {
      supabaseClubMemberCounts[widget.club.id] = cached - 1;
    }
  }

  /// Owner tap → choose: view profile, assign/edit a club role, or remove role.
  void _openMemberActions(User member) {
    final hasRole = widget.club.boardMemberIds.contains(member.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.person_outline, color: AppColors.text),
              title: Text(
                AppLocalizations.of(context)!.viewProfileLabel,
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _viewProfile(member);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.workspace_premium_outlined,
                color: AppColors.primaryRed,
              ),
              title: Text(
                hasRole
                    ? AppLocalizations.of(context)!.editClubRoleLabel
                    : AppLocalizations.of(context)!.assignClubRoleLabel,
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _assignRole(member);
              },
            ),
            if (hasRole)
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                ),
                title: Text(
                  AppLocalizations.of(context)!.removeFromBoardLabel,
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _removeRole(member);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.person_remove_outlined,
                color: Colors.red,
              ),
              title: Text(
                AppLocalizations.of(context)!.removeFromClubLabel,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _removeMember(member);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _assignRole(User member) async {
    final current = widget.club.boardMemberTitles[member.id] ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _BoardTitleDialog(memberName: member.name, initialTitle: current),
    );
    if (result == null || !mounted) return;

    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: member.id,
        isBoardMember: result.trim().isNotEmpty,
        title: result,
      );
    } catch (_) {
      if (!mounted) return;
      _showClubRoleError(context);
      return;
    }
    if (!mounted) return;
    setState(() => _members = _sortMembers(_members));
  }

  Future<void> _removeRole(User member) async {
    try {
      await studentClubRoleService.setBoardMembership(
        club: widget.club,
        userId: member.id,
        isBoardMember: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showClubRoleError(context);
      return;
    }
    if (!mounted) return;
    setState(() => _members = _sortMembers(_members));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.all(Radius.circular(99)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.members,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.totalCount}',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) LinearProgressIndicator(color: widget.color),
            Expanded(
              child: _members.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          _loading
                              ? AppLocalizations.of(context)!.loadingMembers
                              : _error ??
                                    AppLocalizations.of(
                                      context,
                                    )!.noMembersToShowYet,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      itemCount: _members.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 62,
                        color: AppColors.divider.withValues(alpha: 0.8),
                      ),
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final role = _roleFor(member);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          leading: UserAvatar(
                            userId: member.id,
                            name: member.name,
                            size: 46,
                            fontSize: 16,
                          ),
                          title: Text(
                            userState.displayNameFor(member.id, member.name),
                            style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: role == null
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.workspace_premium_outlined,
                                        size: 13,
                                        color: widget.color,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          role,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: widget.color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          trailing: _isClubAdmin
                              ? Icon(
                                  Icons.more_horiz_rounded,
                                  color: AppColors.secondaryText,
                                )
                              : null,
                          onTap: () {
                            if (_isClubAdmin) {
                              _openMemberActions(member);
                            } else {
                              _viewProfile(member);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Icon tab (icon + label) ──────────────────────────────────────────────────

class _IconTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _IconTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header chat button ────────────────────────────────────────────────────────
// Every student opens the club's canonical community route. Non-members see
// the safe join prompt there; members enter the shared group conversation.
class _ClubChatButton extends StatelessWidget {
  final Club club;
  final VoidCallback onPressed;

  const _ClubChatButton({required this.club, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userState,
      builder: (context, _) {
        final isMember = userState.isFollowing(club.id);
        return GestureDetector(
          key: ValueKey('club-community-button-${club.id}'),
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isMember ? AppColors.lightRed : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                color: isMember
                    ? AppColors.primaryRed
                    : AppColors.secondaryText.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              isMember
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 20,
              color: isMember ? AppColors.primaryRed : AppColors.secondaryText,
            ),
          ),
        );
      },
    );
  }
}
