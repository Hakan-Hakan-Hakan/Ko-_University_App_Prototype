import 'dart:async' show Timer, unawaited;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/calendar/providers/calendar_provider.dart';
import '../features/calendar/providers/calendar_state.dart';
import '../services/app_bootstrap.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/account_switcher_service.dart';
import '../services/auth_service.dart';
import '../services/chat_store.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/mock_data.dart';
import '../services/mock_clubup_profile.dart';
import '../services/notification_navigation.dart';
import '../services/push_notification_service.dart';
import '../onboarding/onboarding_anchors.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/onboarding_service.dart';
import '../onboarding/onboarding_steps.dart';
import '../onboarding/starter_checklist_service.dart';
import '../widgets/lazy_indexed_stack.dart';
import '../widgets/app_pressable.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/club_avatar.dart';
import '../widgets/event_wizard_design.dart';
import '../widgets/user_avatar.dart';
import 'feed_screen.dart';
import 'this_week_screen.dart';
// my_calendar_screen is used from feed_screen, not nav;
import 'explore_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'admin_dashboard.dart';
import 'create_event_screen.dart';
import 'create_post_screen.dart';
import 'notifications_screen.dart';
import 'moderation_center_screen.dart';
import '../services/guest_session.dart';
import '../widgets/guest_notice_dialog.dart';

class MainNavScreen extends ConsumerStatefulWidget {
  final bool isAdmin;
  final VoidCallback? onLogout;
  const MainNavScreen({super.key, required this.isAdmin, this.onLogout});

  @override
  ConsumerState<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends ConsumerState<MainNavScreen>
    with TickerProviderStateMixin {
  static const double _desktopNavigationBreakpoint = 960;
  static const double _desktopSidebarWidth = 248;
  static const double _desktopContentMaxWidth = 1040;

  // Instagram-style nav sizing: scrolling down compacts the bar, upward scroll
  // restores it, and three seconds without interaction gently compacts it too.
  static const double _navBarHeight = 72;
  static const double _navBarShrinkAmount = 20;
  static const double _navShrinkDistance = 80;
  static const double _navExpandThreshold = 8;
  static const Duration _navInactivityDelay = Duration(seconds: 3);
  static const Duration _navIdleShrinkDuration = Duration(milliseconds: 420);
  static const Duration _navSettleShrinkDuration = Duration(milliseconds: 280);

  int _selectedIndex = 0;
  TutorialLaunchSource? _tutorialLaunchSource;
  bool _accountSwitcherOpening = false;
  double? _navDragDx;
  final ChatsController _chatsController = ChatsController();
  final FeedController _feedController = FeedController();
  late final AnimationController _tabTransitionController;
  late final AnimationController _navShrinkController;
  Timer? _navInactivityTimer;
  bool _navInteractionActive = false;
  bool _navExpanding = false;
  double _navUpwardDelta = 0;

  // Built once and never replaced by nav taps or content-creation callbacks,
  // so IndexedStack sees the same widget instances and Flutter's element-
  // identity fast path skips rebuilding every off-screen tab. Each tab
  // listens for theme/locale changes itself, so this list doesn't need to be
  // rebuilt for that either — only this screen's own chrome (the nav bar)
  // does, via _onThemeOrLocaleChanged below.
  late final List<Widget> _screens = _buildScreens();

  List<Widget> _buildScreens() => <Widget>[
    FeedScreen(controller: _feedController), // 0
    ThisWeekScreen(isTutorialHost: true), // 1
    ExploreScreen(), // 2
    if (_isPlatformModerator)
      const ModerationCenterScreen() // 3
    else
      ChatsScreen(
        isTutorialHost: true,
        controller: _chatsController,
        // `club-chats-empty` 140:39 / 140:43 route out to Search and This Week.
        onSelectTab: _selectNavIndex,
      ), // 3
    ProfileScreen(onLogout: () => widget.onLogout?.call()), // 4
    if (widget.isAdmin) AdminDashboard(onLogout: widget.onLogout), // 5
  ];

  String get _currentUserId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1,
    );
    // Driven directly from scroll deltas, so its own duration only applies to
    // the settle/restore animations below.
    _navShrinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );
    onboardingService.replayRequests.addListener(_onOnboardingReplayRequested);
    onboardingService.tabRequests.addListener(_onTabRequested);
    pushNotificationService.addListener(_onPushNotificationOpened);
    themeService.addListener(_onThemeOrLocaleChanged);
    localeService.addListener(_onThemeOrLocaleChanged);
    accountSwitcherService.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startInitialExperience());
      unawaited(
        appBootstrap.ready.then((_) {
          if (!mounted || !appBootstrap.localDataReady) return;
          unawaited(chatStore.startChatV2Sync(_currentUserId));
        }),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onPushNotificationOpened(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleNavInactivity();
    });
  }

  void _onPushNotificationOpened() {
    final target = pushNotificationService.takePendingTarget();
    if (!mounted || target == null) return;
    unawaited(_openPushNotificationTarget(target));
  }

  Future<void> _openPushNotificationTarget(
    PushNotificationTarget target,
  ) async {
    await appBootstrap.ready;
    if (!mounted) return;

    // ClubUp uses this navigation position for moderation and has no chat tab.
    if (_isPlatformModerator && target.isChat) return;

    // Other club admins may only use their managed community. Never switch
    // them to stale student-only messaging destinations.
    if (ChatStore.isAdminAccountId(_currentUserId) &&
        target.isChat &&
        target.type != 'club_chat' &&
        target.type != 'club_inbox') {
      return;
    }

    final selectedIndex = switch (target.type) {
      'direct_message' || 'group_chat' || 'club_chat' || 'club_inbox' => 3,
      'event' => 1,
      'club' || 'user' => 2,
      _ => 0,
    };
    if (_selectedIndex != selectedIndex) {
      _selectNavIndex(selectedIndex);
    }
    if (target.type == 'notification') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      );
      return;
    }
    await openNotificationTarget(
      context,
      target,
      currentUserId: _currentUserId,
    );
  }

  void _onThemeOrLocaleChanged() {
    // Only this screen's own chrome (nav bar colors/labels) needs to redraw;
    // _screens is left untouched so the tab bodies aren't force-rebuilt.
    if (mounted) setState(() {});
  }

  // Do not interrupt Home with the welcome/tutorial overlay. The tour remains
  // available as an explicit replay from Settings.
  Future<void> _startInitialExperience() async {
    if (!mounted) return;
    // The exception is the guest joyride. First say plainly that the campus is
    // fabricated — a visitor must not mistake the seeded students, clubs and
    // messages for real ones, or think their likes were kept — and only then
    // start the tour, which is the point of the visit and the one surface that
    // walks every tab. `manual` is deliberate: it keeps
    // `onboardingService.complete()` out of the picture and skips the calendar
    // permission prompt an automatic run ends with, so the joyride leaves no
    // trace on the visitor's device.
    if (guestSession.isActive) {
      await showGuestNoticeDialog(context);
      if (!mounted) return;
      _startOnboarding(TutorialLaunchSource.manual);
      return;
    }
    await _requestCalendarIfNeeded();
  }

  void _onOnboardingReplayRequested() {
    if (!mounted || !(authService.isStudentSession || _isClubAdmin)) return;
    _startOnboarding(TutorialLaunchSource.manual);
  }

  void _onTabRequested() {
    final index = onboardingService.tabRequests.value;
    if (index == null || !mounted) return;
    _selectNavIndex(index);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if ((_isClubAdmin || _isLinkedClubAccount) && _selectedIndex == 2) {
      setState(() => _selectedIndex = 0);
      return;
    }
    setState(() {});
  }

  void _startOnboarding(TutorialLaunchSource source) {
    if (_tutorialLaunchSource != null) return;
    // The tour spotlights individual nav items, so it always gets the full bar.
    _navInactivityTimer?.cancel();
    _resetNavShrink();
    setState(() {
      _selectedIndex = 0;
      _tutorialLaunchSource = source;
    });
  }

  // The flow starts the animated return Home before invoking this callback;
  // this method owns persistence and the post-tour checklist lifecycle.
  Future<void> _finishOnboarding() async {
    final source = _tutorialLaunchSource;
    if (source == null) return;
    final profileId = _currentUserId;
    setState(() => _tutorialLaunchSource = null);
    _scheduleNavInactivity();
    try {
      await onboardingService.finish(profileId, source: source);
    } catch (error) {
      debugPrint('Could not persist tutorial completion: $error');
    }
    if (!mounted) return;
    if (authService.isStudentSession) {
      await starterChecklistService.startFor(profileId);
    }
    if (mounted && source == TutorialLaunchSource.automatic) {
      await _requestCalendarIfNeeded();
    }
  }

  void _onOnboardingStepChanged(OnboardingStep step) {
    if (_selectedIndex == step.tabIndex) return;
    _resetNavShrink();
    _tabTransitionController.forward(from: 0);
    setState(() => _selectedIndex = step.tabIndex);
    if (step.tabIndex == 3 && !_isPlatformModerator) {
      _chatsController.showStudents();
    }
  }

  Future<void> _requestCalendarIfNeeded() async {
    final service = ref.read(calendarServiceProvider);
    final permission = await service.checkPermission();
    if (!mounted) return;
    if (permission == CalendarPermissionState.granted ||
        permission == CalendarPermissionState.permanentlyDenied ||
        permission == CalendarPermissionState.restricted) {
      return;
    }
    await service.requestPermission();
  }

  @override
  void dispose() {
    onboardingService.replayRequests.removeListener(
      _onOnboardingReplayRequested,
    );
    onboardingService.tabRequests.removeListener(_onTabRequested);
    pushNotificationService.removeListener(_onPushNotificationOpened);
    themeService.removeListener(_onThemeOrLocaleChanged);
    localeService.removeListener(_onThemeOrLocaleChanged);
    accountSwitcherService.removeListener(_onAccountChanged);
    _navInactivityTimer?.cancel();
    unawaited(chatStore.stopChatV2Sync());
    _chatsController.dispose();
    _feedController.dispose();
    _tabTransitionController.dispose();
    _navShrinkController.dispose();
    super.dispose();
  }

  // Chat unreads clear per-thread when a conversation is opened (see
  // ChatThreadScreen), so unlike the old Alerts tab there's nothing to
  // mark read when the Chats tab itself is selected. ClubUp's tab at this
  // index is Moderation, so it must not touch chat state.
  void _selectNavIndex(int index) {
    // Any destination tap reveals the full bar, including tapping the already
    // selected tab. Inactivity can compact it again after the shared delay.
    _resetNavShrink();
    if (index == 0 && _selectedIndex == 0) {
      _feedController.scrollToTop();
      return;
    }
    if (index == 3 && !_isPlatformModerator) _chatsController.showStudents();
    if (_selectedIndex != index) {
      // The incoming tab has its own scroll position, so the bar starts over
      // in its full form rather than inheriting the previous tab's shrink.
      if (_tutorialLaunchSource != null) {
        _tabTransitionController.forward(from: 0);
      }
      setState(() => _selectedIndex = index);
    }
  }

  // Compacts the bar as the user scrolls down and restores it once they move
  // back up, matching Instagram's floating tab bar. The shrink follows the
  // finger rather than snapping, so the bar never jumps mid-drag.
  bool _handleContentScroll(ScrollNotification notification) {
    // Horizontal rails (events, media carousels) and the tour must not move it.
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_tutorialLaunchSource != null) return false;

    if (notification is ScrollUpdateNotification) {
      _scheduleNavInactivity();
      // At rest against the top — including pull-to-refresh overscroll — the
      // bar always belongs in its full form.
      if (notification.metrics.extentBefore <= 0) {
        _navUpwardDelta = 0;
        _expandNav();
        return false;
      }
      final delta = notification.scrollDelta ?? 0;
      if (delta > 0) {
        _navUpwardDelta = 0;
        _navShrinkController.stop();
        _navExpanding = false;
        _navShrinkController.value =
            (_navShrinkController.value + delta / _navShrinkDistance).clamp(
              0.0,
              1.0,
            );
      } else if (delta < 0) {
        // A deliberate upward move restores the bar; the sub-pixel jitter of a
        // settling fling or a bounce does not.
        _navUpwardDelta -= delta;
        if (_navUpwardDelta >= _navExpandThreshold) _expandNav();
      }
    } else if (notification is ScrollEndNotification) {
      _settleNav();
      _scheduleNavInactivity();
    }
    return false;
  }

  void _expandNav() {
    _scheduleNavInactivity();
    if (_navShrinkController.value == 0 || _navExpanding) return;
    _navExpanding = true;
    _navShrinkController
        .animateTo(0, curve: Curves.easeOutCubic)
        .whenCompleteOrCancel(() => _navExpanding = false);
  }

  /// A downward scroll that ends before the bar is fully compact would
  /// otherwise leave it at an arbitrary in-between size. Downward scrolling
  /// only ever settles compact — only an upward move brings the bar back.
  void _settleNav() {
    final value = _navShrinkController.value;
    if (value <= 0 || value >= 1 || _navExpanding) return;
    _navShrinkController.animateTo(
      1,
      duration: _navSettleShrinkDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _resetNavShrink() {
    _navShrinkController.stop();
    _navExpanding = false;
    _navUpwardDelta = 0;
    _navShrinkController.value = 0;
    _scheduleNavInactivity();
  }

  void _scheduleNavInactivity() {
    _navInactivityTimer?.cancel();
    if (!mounted ||
        _navInteractionActive ||
        _tutorialLaunchSource != null ||
        _accountSwitcherOpening) {
      return;
    }
    _navInactivityTimer = Timer(_navInactivityDelay, _shrinkNavAfterInactivity);
  }

  void _shrinkNavAfterInactivity() {
    _navInactivityTimer = null;
    if (!mounted ||
        _navInteractionActive ||
        _tutorialLaunchSource != null ||
        _accountSwitcherOpening ||
        MediaQuery.sizeOf(context).width >= _desktopNavigationBreakpoint ||
        _navShrinkController.value >= 1) {
      return;
    }
    _navExpanding = false;
    _navUpwardDelta = 0;
    _navShrinkController.animateTo(
      1,
      duration: _navIdleShrinkDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _onNavPointerDown(PointerDownEvent event) {
    _navInteractionActive = true;
    _navInactivityTimer?.cancel();
    _expandNav();
  }

  void _onNavPointerFinished(PointerEvent event) {
    _navInteractionActive = false;
    _scheduleNavInactivity();
  }

  void _handleNavDragPosition(
    Offset localPosition,
    double barWidth,
    List<_NavSlot> slots,
  ) {
    if (slots.isEmpty || barWidth <= 0) return;

    final clampedDx = localPosition.dx.clamp(0.0, barWidth).toDouble();
    final slotWidth = barWidth / slots.length;
    final slotIndex = (clampedDx / slotWidth).floor().clamp(
      0,
      slots.length - 1,
    );
    final navIndex = slots[slotIndex].index;
    final enteringChats =
        navIndex == 3 && _selectedIndex != 3 && !_isPlatformModerator;

    setState(() {
      _navDragDx = clampedDx;
      if (navIndex != null) {
        _selectedIndex = navIndex;
      }
    });
    if (enteringChats) _chatsController.showStudents();
  }

  void _handleNavLongPressStart(
    Offset localPosition,
    double barWidth,
    List<_NavSlot> slots,
  ) {
    if (_accountSwitcherOpening || slots.isEmpty || barWidth <= 0) return;
    _resetNavShrink();
    final slotWidth = barWidth / slots.length;
    final slotIndex = (localPosition.dx / slotWidth).floor().clamp(
      0,
      slots.length - 1,
    );
    if (slots[slotIndex].index == 4) {
      _endNavDrag();
      unawaited(_openAccountSwitcher());
      return;
    }
    _handleNavDragPosition(localPosition, barWidth, slots);
  }

  Future<void> _openAccountSwitcher() async {
    if (_accountSwitcherOpening || !mounted) return;
    _accountSwitcherOpening = true;
    _resetNavShrink();
    HapticFeedback.mediumImpact();
    try {
      await showAccountSwitcherSheet(context);
    } finally {
      _accountSwitcherOpening = false;
      _scheduleNavInactivity();
    }
  }

  void _endNavDrag() {
    if (_navDragDx == null) return;
    setState(() => _navDragDx = null);
  }

  bool get _isClubAdmin {
    final admin = authService.currentAdmin;
    return admin != null && !isClubUpAdmin(admin);
  }

  bool get _isLinkedClubAccount => accountSwitcherService.isClubAccountActive;

  bool get _isPlatformModerator => isClubUpAdmin(authService.currentAdmin);

  void _openCreateEvent() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        // FeedScreen/ThisWeekScreen refresh themselves via contentStore's
        // change notification — no need to rebuild this screen too.
        builder: (_) => const CreateEventScreen(),
      ),
    );
  }

  // Posts are authored inline on Club Home. The center + is reserved for the
  // event workflow for both dedicated admins and linked club accounts.
  void _openCreatePost() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CreatePostScreen(),
      ),
    );
  }

  void _onAddTap() {
    _resetNavShrink();
    // `plus-menu` 297:8 — the handoff's + opens a chooser; Create Post was
    // previously unreachable from here.
    unawaited(
      showEventWizardCreateSheet(
        context,
        onPost: _openCreatePost,
        onEvent: _openCreateEvent,
      ),
    );
  }

  Widget _buildTabContent() {
    return AnimatedBuilder(
      animation: _tabTransitionController,
      child: LazyIndexedStack(index: _selectedIndex, children: _screens),
      builder: (context, child) {
        final motion = Curves.easeOutCubic.transform(
          _tabTransitionController.value,
        );
        return Opacity(
          opacity: 0.88 + (0.12 * motion),
          child: Transform.scale(scale: 0.985 + (0.015 * motion), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // BackdropGroup lets the nav bar's and the feed top bar's grouped blurs
    // share a single backdrop readback per frame instead of one each.
    return BackdropGroup(
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useDesktopNavigation =
                    constraints.maxWidth >= _desktopNavigationBreakpoint;
                final tabContent = _buildTabContent();

                // ChatStore can notify for message delivery, read receipts,
                // typing state, and sync progress. Only the unread badge
                // depends on those updates, so the mounted tab content is
                // passed through unchanged while the navigation chrome
                // refreshes.
                return _UnreadNavBar(
                  unread: () => chatStore.totalUnreadFor(_currentUserId),
                  builder: (context, unreadChats) {
                    if (useDesktopNavigation) {
                      return Scaffold(
                        backgroundColor: AppColors.background,
                        body: Row(
                          children: [
                            SizedBox(
                              width: _desktopSidebarWidth,
                              child: _buildDesktopSidebar(context, unreadChats),
                            ),
                            Expanded(
                              child: _DesktopContentCanvas(
                                maxWidth: _desktopContentMaxWidth,
                                child: tabContent,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Scaffold(
                      extendBody: true,
                      body: NotificationListener<ScrollNotification>(
                        onNotification: _handleContentScroll,
                        child: tabContent,
                      ),
                      // Only the bar itself listens to the shrink animation, so
                      // the mounted tab content is never rebuilt while scrolling.
                      bottomNavigationBar: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onNavPointerDown,
                        onPointerUp: _onNavPointerFinished,
                        onPointerCancel: _onNavPointerFinished,
                        child: AnimatedBuilder(
                          animation: _navShrinkController,
                          builder: (context, _) => _buildBottomNav(
                            context,
                            unreadChats,
                            _navShrinkController.value,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_tutorialLaunchSource != null)
            Positioned.fill(
              child: OnboardingFlow(
                steps: _isClubAdmin
                    ? clubAdminOnboardingSteps(
                        usesModerationTab: _isPlatformModerator,
                      )
                    : studentOnboardingSteps(),
                onStepChanged: _onOnboardingStepChanged,
                onComplete: _finishOnboarding,
                onSkip: _finishOnboarding,
                onNavigateHome: () => _selectNavIndex(0),
              ),
            ),
        ],
      ),
    );
  }

  List<_NavSlot> _buildNavSlots(BuildContext context, int unreadChats) {
    return <_NavSlot>[
      _NavSlot(
        index: 0,
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: AppLocalizations.of(context)!.home,
      ),
      _NavSlot(
        index: 1,
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today_rounded,
        label: AppLocalizations.of(context)!.events,
      ),
      // Platform moderators still need campus-wide discovery so they can find
      // the people, clubs, posts, and events they are responsible for
      // reviewing. Ordinary club admins keep their focused club workflow.
      if (!_isClubAdmin && !_isLinkedClubAccount)
        _NavSlot(
          index: 2,
          icon: Icons.search_outlined,
          activeIcon: Icons.search_rounded,
          label: AppLocalizations.of(context)!.search,
        ),
      if (_isClubAdmin || _isLinkedClubAccount) const _NavSlot.center(),
      if (_isPlatformModerator)
        _NavSlot(
          index: 3,
          icon: Icons.shield_outlined,
          activeIcon: Icons.shield_rounded,
          label: S.moderation,
        )
      else
        _NavSlot(
          index: 3,
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_bubble_rounded,
          label: S.chats,
          badge: unreadChats,
        ),
      if (!_isPlatformModerator)
        _NavSlot(
          index: 4,
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: AppLocalizations.of(context)!.profile,
        ),
      if (widget.isAdmin)
        _NavSlot(
          index: 5,
          icon: Icons.admin_panel_settings_outlined,
          activeIcon: Icons.admin_panel_settings_rounded,
          label: AppLocalizations.of(context)!.admin,
        ),
    ];
  }

  /// Uses the same frontend avatar state as profile screens and account rows.
  /// No fetch is started here: photo updates flow through [UserAvatar] and
  /// [ClubAvatar], and both widgets already own their initials fallback.
  Widget? _buildProfileNavAvatar(double size) {
    final linkedClub = accountSwitcherService.activeClub;
    final admin = authService.currentAdmin;

    if (linkedClub != null || (_isClubAdmin && admin != null)) {
      final club = linkedClub ?? clubForId(admin!.id);
      return IgnorePointer(
        key: ValueKey<String>(
          'profile-nav-club-avatar-${club?.id ?? admin!.id}',
        ),
        child: ClubAvatar(
          clubId: club?.id ?? admin!.id,
          clubName: club?.name ?? admin!.name,
          color: AppColors.primaryRed,
          imageUrl: club?.logoUrl,
          profilePhotoFallbackId: admin?.id,
          shape: 'circle',
          size: size,
          fontSize: size * 0.42,
        ),
      );
    }

    final user = authService.currentUser;
    if (user == null) return null;
    return IgnorePointer(
      key: ValueKey<String>('profile-nav-user-avatar-${user.id}'),
      child: UserAvatar(
        userId: user.id,
        name: user.name,
        size: size,
        fontSize: size * 0.42,
      ),
    );
  }

  Key? _onboardingKeyForNavIndex(int index) {
    return switch (index) {
      0 => onboardingAnchors.keyFor(OnboardingAnchors.navHome),
      1 => onboardingAnchors.keyFor(OnboardingAnchors.navEvents),
      2 => onboardingAnchors.keyFor(OnboardingAnchors.navSearch),
      3 => onboardingAnchors.keyFor(OnboardingAnchors.navChats),
      4 => onboardingAnchors.keyFor(OnboardingAnchors.navProfile),
      _ => null,
    };
  }

  Widget _buildDesktopSidebar(BuildContext context, int unreadChats) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slots = _buildNavSlots(context, unreadChats);

    return Container(
      // The student tour teaches the whole navigation surface first. On wide
      // layouts the sidebar is that surface, so it must share the same anchor
      // as the mobile capsule.
      key: onboardingAnchors.keyFor(OnboardingAnchors.navBar),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(
            color: AppColors.divider.withValues(alpha: isDark ? 0.7 : 0.9),
          ),
        ),
      ),
      child: SafeArea(
        key: const ValueKey<String>('desktop-navigation-sidebar'),
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(13)),
                    child: Image.asset(
                      'assets/branding/clubup_app_icon_1024.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ClubUp',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                        ),
                        Text(
                          kIsWeb ? 'KOÇ UNIVERSITY · WEB' : 'KOÇ UNIVERSITY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                children: [
                  for (final slot in slots) ...[
                    if (slot.isCenterButton)
                      _DesktopCreateButton(
                        key: onboardingAnchors.keyFor(
                          OnboardingAnchors.clubCreateButton,
                        ),
                        label: AppLocalizations.of(context)!.newEventTitle,
                        onTap: _onAddTap,
                      )
                    else
                      _DesktopNavItem(
                        key: _onboardingKeyForNavIndex(slot.index!),
                        icon: slot.icon!,
                        activeIcon: slot.activeIcon!,
                        avatar: slot.index == 4
                            ? _buildProfileNavAvatar(26)
                            : null,
                        label: slot.label!,
                        selected: _selectedIndex == slot.index,
                        badge: slot.badge,
                        onTap: () => _selectNavIndex(slot.index!),
                        onLongPress: slot.index == 4
                            ? () => unawaited(_openAccountSwitcher())
                            : null,
                      ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Text(
                'ClubUp',
                style: TextStyle(
                  color: AppColors.secondaryText.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [shrink] runs 0 (full size) to 1 (the compact scrolled form).
  Widget _buildBottomNav(BuildContext context, int unreadChats, double shrink) {
    final isDark = themeService.isDark;

    // Ordered slots so the sliding highlight can be positioned purely from
    // list index, regardless of which tabs are hidden for admins.
    final slots = _buildNavSlots(context, unreadChats);

    final slotCount = slots.length;
    final selectedSlot = slots.indexWhere((s) => s.index == _selectedIndex);
    final barHeight = _navBarHeight - (_navBarShrinkAmount * shrink);

    return SafeArea(
      key: const ValueKey<String>('mobile-bottom-navigation'),
      top: false,
      child: Padding(
        // The pill also narrows as it shrinks, so it reads as one object
        // pulling in rather than just losing height.
        padding: EdgeInsets.fromLTRB(
          16 + (22 * shrink),
          0,
          16 + (22 * shrink),
          4,
        ),
        child: ClipRRect(
          // `tut-home-nav` spotlights the bar as one 30-radius shape rather
          // than a single tab, so the whole capsule is the tour's anchor.
          key: onboardingAnchors.keyFor(OnboardingAnchors.navBar),
          borderRadius: BorderRadius.all(Radius.circular(30)),
          child: BackdropFilter.grouped(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(30)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.008),
                          Colors.black.withValues(alpha: 0.015),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.03),
                          Colors.white.withValues(alpha: 0.01),
                        ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.10),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.03),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final slotWidth = slotCount > 0
                      ? barWidth / slotCount
                      : barWidth;
                  final isNavDragging = _navDragDx != null;
                  final capsuleWidth = slotWidth - 12;
                  final capsuleLeft = isNavDragging
                      ? (_navDragDx! - capsuleWidth / 2)
                            .clamp(6.0, barWidth - capsuleWidth - 6)
                            .toDouble()
                      : slotWidth * selectedSlot + 6;
                  final underlineLeft = isNavDragging
                      ? (_navDragDx! - slotWidth / 2)
                            .clamp(0.0, barWidth - slotWidth)
                            .toDouble()
                      : slotWidth * selectedSlot;

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: (details) => _handleNavLongPressStart(
                      details.localPosition,
                      barWidth,
                      slots,
                    ),
                    onLongPressMoveUpdate: (details) => _handleNavDragPosition(
                      details.localPosition,
                      barWidth,
                      slots,
                    ),
                    onLongPressEnd: (_) => _endNavDrag(),
                    onLongPressCancel: _endNavDrag,
                    child: Stack(
                      children: [
                        // Soft inner highlight sheen along the top edge.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(30),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: isDark ? 0.015 : 0.04,
                                    ),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Brighter glass capsule sliding under the selected tab.
                        // No blur here (that's still on the outer bar) — a
                        // solid-ish highlight is visually close at a fraction
                        // of the compositing cost of two stacked BackdropFilters.
                        if (selectedSlot != -1)
                          AnimatedPositioned(
                            duration: isNavDragging
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: capsuleLeft,
                            top: 8 - (3 * shrink),
                            width: capsuleWidth,
                            height: barHeight - 16 + (6 * shrink),
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(22),
                                  ),
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.white.withValues(alpha: 0.36),
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: isDark ? 0.17 : 0.52,
                                    ),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryRed.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Thin maroon underline with a soft glow, sliding in
                        // step with the capsule above.
                        if (selectedSlot != -1)
                          AnimatedPositioned(
                            duration: isNavDragging
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: underlineLeft,
                            bottom: 6 - (2 * shrink),
                            width: slotWidth,
                            height: 3,
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  width: 22,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryRed,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(100),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryRed.withValues(
                                          alpha: 0.55,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Foreground row of nav items.
                        Positioned.fill(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              for (final slot in slots)
                                slot.isCenterButton
                                    ? _CenterAddButton(
                                        key: onboardingAnchors.keyFor(
                                          OnboardingAnchors.clubCreateButton,
                                        ),
                                        shrink: shrink,
                                        onTap: _onAddTap,
                                      )
                                    : _NavItem(
                                        // The super-admin Dashboard slot (5) has
                                        // no tour step, and reusing navProfile
                                        // there would mount one GlobalKey twice.
                                        key: _onboardingKeyForNavIndex(
                                          slot.index!,
                                        ),
                                        icon: slot.icon!,
                                        activeIcon: slot.activeIcon!,
                                        avatar: slot.index == 4
                                            ? _buildProfileNavAvatar(
                                                24 - (2 * shrink),
                                              )
                                            : null,
                                        label: slot.label!,
                                        selected: _selectedIndex == slot.index,
                                        badge: slot.badge,
                                        shrink: shrink,
                                        onTap: () =>
                                            _selectNavIndex(slot.index!),
                                        onLongPress: slot.index == 4
                                            ? () => unawaited(
                                                _openAccountSwitcher(),
                                              )
                                            : null,
                                      ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the phone-first tab screens readable on wide monitors. The nested
/// MediaQuery reports the actual canvas width, so existing cards and media
/// that size themselves from MediaQuery do not accidentally use the full
/// browser window (which also includes the sidebar and outer gutters).
class _DesktopContentCanvas extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const _DesktopContentCanvas({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(0.0, maxWidth).toDouble();
          final media = MediaQuery.of(context);

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: MediaQuery(
                data: media.copyWith(size: Size(width, constraints.maxHeight)),
                child: ClipRect(child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final Widget? avatar;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DesktopNavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    this.avatar,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    final foreground = selected
        ? AppColors.primaryRed
        : AppColors.secondaryText;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryRed.withValues(alpha: 0.11)
                    : Colors.transparent,
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? AppColors.primaryRed.withValues(alpha: 0.2)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child:
                        avatar ??
                        Icon(
                          selected ? activeIcon : icon,
                          key: ValueKey<bool>(selected),
                          color: foreground,
                          size: 23,
                        ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.text : foreground,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      key: ValueKey<String>('nav-unread-badge-$badge'),
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopCreateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DesktopCreateButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    return Semantics(
      button: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryRed, AppColors.darkRed],
          ),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryRed.withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 23),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Listens to [chatStore] on the nav bar's behalf but only rebuilds when the
/// unread total it reads actually changes. Most of what chatStore notifies
/// about — read receipts, typing signals, realtime sync progress — leaves that
/// number alone, and the nav bar it wraps is an expensive subtree to rebuild.
class _UnreadNavBar extends StatefulWidget {
  final int Function() unread;
  final Widget Function(BuildContext context, int unread) builder;

  const _UnreadNavBar({required this.unread, required this.builder});

  @override
  State<_UnreadNavBar> createState() => _UnreadNavBarState();
}

class _UnreadNavBarState extends State<_UnreadNavBar> {
  late int _unread = widget.unread();

  @override
  void initState() {
    super.initState();
    chatStore.addListener(_onChatStoreChanged);
  }

  @override
  void dispose() {
    chatStore.removeListener(_onChatStoreChanged);
    super.dispose();
  }

  void _onChatStoreChanged() {
    if (!mounted) return;
    final next = widget.unread();
    if (next == _unread) return;
    setState(() => _unread = next);
  }

  @override
  Widget build(BuildContext context) {
    // Re-read here too: the parent rebuilds this for its own reasons (tab
    // change, theme, locale) and the signed-in user can change underneath us,
    // so _unread is refreshed rather than trusted from the last notification.
    _unread = widget.unread();
    return widget.builder(context, _unread);
  }
}

/// Describes one position in the bottom nav row — either a selectable tab
/// or the club-admin center "add" button, which has no selection state.
class _NavSlot {
  final int? index;
  final IconData? icon;
  final IconData? activeIcon;
  final String? label;
  final int badge;
  final bool isCenterButton;

  _NavSlot({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  }) : isCenterButton = false;

  const _NavSlot.center()
    : index = null,
      icon = null,
      activeIcon = null,
      label = null,
      badge = 0,
      isCenterButton = true;
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final Widget? avatar;
  final String label;
  final bool selected;
  final int badge;

  /// 0 = full bar with labels, 1 = compact scrolled bar (icons only).
  final double shrink;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    this.avatar,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.badge = 0,
    this.shrink = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Labels fade out over the first half of the shrink so they are gone well
    // before the row runs out of room for them.
    final labelOpacity = (1 - (shrink * 2)).clamp(0.0, 1.0);

    return Expanded(
      child: AppPressable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        pressedScale: 0.94,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8 - (4 * shrink)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: selected ? 1.0 : 0.82,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      avatar ??
                          Icon(
                            selected ? activeIcon : icon,
                            color: selected
                                ? AppColors.primaryRed
                                : AppColors.secondaryText,
                            size: 24 - (2 * shrink),
                          ),
                      if (badge > 0)
                        Positioned(
                          top: -4,
                          right: -6,
                          child: Container(
                            key: ValueKey<String>('nav-unread-badge-$badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 15,
                              minHeight: 15,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryRed,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$badge',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Collapsed rather than hidden, so the row's height shrinks with
              // the bar instead of overflowing it.
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: (1 - shrink).clamp(0.0, 1.0),
                  child: Opacity(
                    opacity: labelOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 10,
                            color: selected
                                ? AppColors.primaryRed
                                : AppColors.secondaryText,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                          child: Text(label),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterAddButton extends StatefulWidget {
  final VoidCallback onTap;

  /// 0 = full bar, 1 = compact scrolled bar.
  final double shrink;
  const _CenterAddButton({super.key, required this.onTap, this.shrink = 0});

  @override
  State<_CenterAddButton> createState() => _CenterAddButtonState();
}

class _CenterAddButtonState extends State<_CenterAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  late final Animation<double> _turns = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 0.125), weight: 42),
    TweenSequenceItem(tween: Tween(begin: 0.125, end: -0.025), weight: 28),
    TweenSequenceItem(tween: Tween(begin: -0.025, end: 0), weight: 30),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  void _handleTap() {
    if (_controller.isAnimating) return;
    HapticFeedback.lightImpact();
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
    widget.onTap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: AppPressable(
          onTap: _handleTap,
          pressedScale: 0.92,
          child: Container(
            width: 52 - (14 * widget.shrink),
            height: 52 - (14 * widget.shrink),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryRed, AppColors.darkRed],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryRed.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: RotationTransition(
              key: const ValueKey('center-add-icon-motion'),
              turns: _turns,
              child: Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28 - (7 * widget.shrink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
