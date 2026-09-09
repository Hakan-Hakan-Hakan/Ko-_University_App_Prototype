import 'dart:async';
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/app_launch_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_flow_screen.dart';
import 'screens/update_required_screen.dart';
import 'screens/terms_acceptance_screen.dart';
// import 'screens/feed_screen.dart';
// import 'screens/admin_dashboard.dart';
import 'screens/main_nav_screen.dart';
import 'screens/theme_choice_screen.dart';
import 'screens/language_choice_screen.dart';
import 'screens/onboarding_carousel_screen.dart';
import 'services/app_bootstrap.dart';
import 'services/auth_service.dart';
import 'services/guest_session.dart';
import 'services/guest_world.dart';
import 'services/mock_clubup_profile.dart';
import 'services/hive_bootstrap.dart';
import 'services/user_prefs_service.dart';
import 'services/chat_store.dart';
import 'services/chat_group_prefs.dart';
import 'services/club_chat_prefs.dart';
import 'services/checkin_store.dart';
import 'services/content_audience_store.dart';
import 'services/content_store.dart';
import 'services/user_state.dart';
import 'services/view_tracker.dart';
import 'services/personalization_service.dart';
import 'services/people_service.dart';
import 'services/poll_store.dart';
import 'services/push_notification_service.dart';
import 'services/theme_service.dart';
import 'services/locale_service.dart';
import 'services/account_preferences_service.dart';
import 'services/calendar_sync_service.dart';
import 'services/supabase_config.dart';
import 'onboarding/onboarding_service.dart';
import 'onboarding/starter_checklist_service.dart';
import 'debug/device_preview.dart';
import 'services/event_cleanup_service.dart';
import 'services/moderation_service.dart';
import 'services/admin_moderation_service.dart';
import 'services/terms_acceptance_service.dart';
import 'services/onboarding_intro_service.dart';
import 'services/app_update_service.dart';
import 'services/startup_log.dart';
import 'theme/app_semantic_colors.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() {
  StartupLog.event('S00_PROCESS_START');
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    StartupLog.event('S01_BINDING_READY');
    FlutterError.onError = (details) {
      StartupLog.uncaught('FLUTTER', details.exception);
      if (!kReleaseMode) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      StartupLog.uncaught('PLATFORM', error);
      return true;
    };
    StartupLog.event('S10_RUN_APP');
    runApp(
      ProviderScope(
        child: DevicePreview(
          enabled: const bool.fromEnvironment('CLUBUP_DEVICE_PREVIEW'),
          child: MyApp(startupInitializer: () => _initializeAfterFirstFrame()),
        ),
      ),
    );
  }, (error, stack) => StartupLog.uncaught('ZONE', error));
}

const _pluginStartupTimeout = Duration(seconds: 5);
const _localStartupTimeout = Duration(seconds: 3);
bool _deferredLocalBootstrapStarted = false;
bool _deferredLocalDataReady = false;
bool _firebaseReady = false;

Future<bool> _guardStartupStage(
  String stage,
  Future<void> Function() operation, {
  Duration timeout = _pluginStartupTimeout,
}) async {
  StartupLog.begin(stage);
  final outcome = await runBoundedStartupOperation(operation, timeout);
  final result = switch (outcome.result) {
    StartupOperationResult.completed => 'ok',
    StartupOperationResult.timedOut => 'timeout',
    StartupOperationResult.failed => 'error',
  };
  StartupLog.end(stage, result: result, error: outcome.error);
  return outcome.result == StartupOperationResult.completed;
}

Future<void> _initializeAfterFirstFrame() async {
  var supabaseConfigured = false;
  try {
    SupabaseConfig.validate();
    supabaseConfigured = SupabaseConfig.isConfigured;
  } catch (error) {
    StartupLog.event(
      'S04_SUPABASE_BEGIN',
      result: 'config_error',
      error: error,
    );
  }

  final results = await Future.wait<bool>([
    if (PushNotificationService.isSupported)
      _guardStartupStage('S02_FIREBASE_BEGIN', () async {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      })
    else
      Future.value(false),
    if (supabaseConfigured)
      _guardStartupStage('S04_SUPABASE_BEGIN', () async {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: SupabaseConfig.clientKey,
          authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
          debug: false,
        );
      })
    else
      Future.value(false),
    _guardStartupStage('S04_HIVE_BEGIN', hiveBootstrap.initialize),
    _guardStartupStage(
      'S01_BUILD_INFO',
      StartupLog.loadBuildInfo,
      timeout: _localStartupTimeout,
    ),
  ]);
  _firebaseReady = results[0];
  StartupLog.event('S03_FIREBASE_END', result: results[0] ? 'ok' : 'fallback');
  StartupLog.event('S05_SUPABASE_END', result: results[1] ? 'ok' : 'fallback');
  final hiveReady = results[2];

  if (hiveReady) {
    await Future.wait([
      _guardStartupStage(
        'S05_THEME_LOCAL',
        themeService.initialize,
        timeout: _localStartupTimeout,
      ),
      _guardStartupStage(
        'S05_LOCALE_LOCAL',
        localeService.initialize,
        timeout: _localStartupTimeout,
      ),
      _guardStartupStage(
        'S05_TERMS_LOCAL',
        termsAcceptanceService.initialize,
        timeout: _localStartupTimeout,
      ),
      _guardStartupStage(
        'S05_INTRO_LOCAL',
        onboardingIntroService.initialize,
        timeout: _localStartupTimeout,
      ),
    ]);
    _startDeferredLocalBootstrap();
  } else {
    appBootstrap.ready = Future.value();
  }

  StartupLog.begin('S06_SESSION_RESTORE_BEGIN');
  var restoredSession = false;
  if (results[1]) {
    restoredSession = await authService.restorePersistedSession();
  }
  StartupLog.end(
    'S07_SESSION_RESTORE_END',
    result: results[1]
        ? authService.lastSessionRestorationResult.name
        : 'supabase_unavailable',
  );

  if (restoredSession && termsAcceptanceService.hasAcceptedCurrentTerms) {
    StartupLog.begin('S08_ACCOUNT_PREFS_BEGIN');
    try {
      await _loadAccountPreferences();
      StartupLog.end(
        'S09_ACCOUNT_PREFS_END',
        result: accountPreferencesService.status.name,
        error: accountPreferencesService.lastError,
      );
    } catch (error) {
      StartupLog.end('S09_ACCOUNT_PREFS_END', result: 'error', error: error);
    }
  } else {
    StartupLog.event('S09_ACCOUNT_PREFS_END', result: 'not_applicable');
  }
}

void _startDeferredLocalBootstrap() {
  _deferredLocalBootstrapStarted = true;
  Future<bool> guarded(Future<void> future) async {
    try {
      await future.timeout(_pluginStartupTimeout);
      return true;
    } catch (_) {
      // Deferred caches are optional and must never surface an unhandled error.
      return false;
    }
  }

  appBootstrap.ready =
      Future.wait([
        guarded(userPrefsService.initialize()),
        guarded(peopleService.initialize()),
        guarded(contentStore.initialize()),
        guarded(chatStore.initialize()),
        guarded(clubChatPrefs.initialize()),
        guarded(chatGroupPrefs.initialize()),
        guarded(checkinStore.initialize()),
        guarded(pollStore.initialize()),
        guarded(contentAudienceStore.initialize()),
        guarded(viewTracker.initialize()),
        guarded(personalizationService.initialize()),
        guarded(calendarSyncService.initialize()),
        guarded(onboardingService.initialize()),
        guarded(starterChecklistService.initialize()),
        guarded(adminModerationService.initialize()),
      ]).then((results) {
        _deferredLocalDataReady = results.every((ready) => ready);
        appBootstrap.localDataReady = _deferredLocalDataReady;
        if (_deferredLocalDataReady) userPrefsService.loadAllPhotos();
      });
}

void _hydrateDeferredLocalData() {
  if (!_deferredLocalBootstrapStarted) return;
  unawaited(
    appBootstrap.ready.then((_) {
      if (!_deferredLocalDataReady) return;
      if (_firebaseReady) {
        unawaited(pushNotificationService.initialize());
      }
      contentStore.applyToLists();
      contentStore.loadBoardMemberIds();
      contentStore.loadBoardMemberTitles();
      final dynNotifs = contentStore.loadDynamicNotifications();
      final removedAdminDmNotificationIds = <String>{};
      if (dynNotifs != null) {
        final compatibleNotifications = dynNotifs.where((notification) {
          final remove =
              notification.targetType == 'message' &&
              ChatStore.isAdminAccountId(notification.userId);
          if (remove) removedAdminDmNotificationIds.add(notification.id);
          return !remove;
        }).toList();
        userState.dynamicNotifications
          ..clear()
          ..addAll(compatibleNotifications);
        if (removedAdminDmNotificationIds.isNotEmpty) {
          unawaited(
            contentStore.saveDynamicNotifications(compatibleNotifications),
          );
        }
      }
      final compatibleReadNotificationIds = contentStore
          .loadReadNotificationIds()
          .where((id) => !removedAdminDmNotificationIds.contains(id));
      userState.replaceReadNotificationIds(compatibleReadNotificationIds);
      if (removedAdminDmNotificationIds.isNotEmpty) {
        unawaited(
          contentStore.saveReadNotificationIds(userState.readNotificationIds),
        );
      }
    }),
  );
}

Future<void> _loadAccountPreferences() async {
  final appUserId = authService.currentUser?.id ?? authService.currentAdmin?.id;
  if (appUserId == null) return;

  final cacheUserId =
      accountPreferencesService.authenticatedUserId ?? appUserId;
  AccountPreferences? preferences;

  try {
    preferences = await accountPreferencesService.loadForCurrentUser();
  } catch (_) {
    // A failed fetch is an unknown state, never evidence that the user has not
    // chosen. Apply this account's cache (or neutral defaults) and continue;
    // the router suppresses preference onboarding until a later fetch succeeds.
  }

  final currentAppUserId =
      authService.currentUser?.id ?? authService.currentAdmin?.id;
  if (currentAppUserId != appUserId) return;

  final languageCode = preferences?.languageCode;
  if (languageCode != null) {
    await localeService.applyAccountLanguage(cacheUserId, languageCode);
  } else {
    await localeService.setLanguage(
      localeService.cachedLanguageFor(cacheUserId) ??
          LocaleService.defaultLanguageCode,
      persistToAccount: false,
    );
  }

  final isDark = preferences?.isDark;
  if (isDark != null) {
    await themeService.applyAccountTheme(cacheUserId, isDark);
  } else {
    await themeService.setDark(
      themeService.cachedThemeFor(cacheUserId) ?? false,
      persistToAccount: false,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.minimumLaunchDuration = const Duration(milliseconds: 2000),
    this.updateService,
    this.startupInitializer,
  });

  final Duration minimumLaunchDuration;
  final AppUpdateService? updateService;
  final Future<void> Function()? startupInitializer;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLaunching = true;
  bool _isBootstrapping = true;
  Timer? _launchTimer;
  bool _showSignUp = false;
  bool _loggedIn = false;
  bool _isPreparingAccountPreferences = false;
  bool _isCheckingForUpdate = true;
  AppUpdateRequirement? _requiredUpdate;
  int _updateCheckGeneration = 0;
  String _signupEmail = '';

  // Snapshotted at app construction so persisting the seen flag cannot remove
  // the carousel mid-launch during an unrelated theme/locale rebuild.
  bool _showIntroThisLaunch = false;

  // Prefs/personalization are loaded once per logged-in user (from _onLogin or
  // the first build that sees the session) — not on every theme/locale
  // rebuild: personalizationService.load ends with notifyListeners(), which
  // must not fire during build.
  String? _prefsLoadedForUserId;
  bool _didLogInitialRoute = false;

  // Theme graphs are built from explicit variants and never read the mutable
  // global preference service.
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;
  ThemeData? _highContrastLightTheme;
  ThemeData? _highContrastDarkTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.minimumLaunchDuration == Duration.zero) {
      _isLaunching = false;
    } else {
      _launchTimer = Timer(widget.minimumLaunchDuration, () {
        if (mounted) setState(() => _isLaunching = false);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_completeStartup());
    });
  }

  Future<void> _completeStartup() async {
    try {
      await (widget.startupInitializer?.call() ?? Future<void>.value());
    } catch (error) {
      StartupLog.uncaught('BOOTSTRAP', error);
    } finally {
      if (mounted) {
        _showIntroThisLaunch = !onboardingIntroService.hasSeenOnceOnDevice;
        if (_showIntroThisLaunch) {
          unawaited(onboardingIntroService.markSeenOnDevice());
        }
        setState(() => _isBootstrapping = false);
        unawaited(_checkForRequiredUpdate(blockWhileChecking: true));
        _hydrateDeferredLocalData();
        if ((authService.currentUser != null ||
                authService.currentAdmin != null) &&
            _termsPermitAuthenticatedAccess) {
          _activateAuthenticatedServices();
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _launchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Returning from the store is the important resume path: the update
      // requirement stays visible until the newly installed build is verified.
      unawaited(
        _checkForRequiredUpdate(blockWhileChecking: _requiredUpdate != null),
      );
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePrefs();
    }
  }

  Future<void> _checkForRequiredUpdate({
    required bool blockWhileChecking,
  }) async {
    final generation = ++_updateCheckGeneration;
    if (blockWhileChecking && mounted) {
      setState(() => _isCheckingForUpdate = true);
    }

    final requiredUpdate = await (widget.updateService ?? appUpdateService)
        .checkForRequiredUpdate();
    if (!mounted || generation != _updateCheckGeneration) return;

    setState(() {
      _requiredUpdate = requiredUpdate;
      // Always release the current check. A resume-triggered check may have
      // replaced the initial blocking check and is intentionally started with
      // blockWhileChecking=false; leaving this conditional here can strand
      // users on the branded launch screen forever.
      _isCheckingForUpdate = false;
    });
  }

  Future<void> _retryUpdateCheck() async {
    await _checkForRequiredUpdate(blockWhileChecking: true);
  }

  void _savePrefs() {
    // App lifecycle events can arrive while the deferred Hive boxes are still
    // opening. In particular, ContentStore uses a late box and cannot be
    // flushed until the whole deferred bootstrap succeeds.
    if (!appBootstrap.localDataReady) return;
    // Nothing from the joyride is written, including on app pause/detach.
    if (guestSession.isActive) return;
    final uid = authService.currentUser?.id ?? authService.currentAdmin?.id;
    if (uid != null) {
      userPrefsService.save(uid);
      personalizationService.save(uid);
    }
    // saveAll rewrites every debounced kind, flushing any pending
    // scheduleSave along the way (pause/detach and logout both land here).
    contentStore.saveAll(userState.dynamicNotifications);
    chatStore.saveAll();
  }

  void _onLogin() {
    // Reaching an authenticated state permanently retires the intro carousel
    // on this device — covers "signed up then logged in" and "logged in on a
    // new device with an existing account" alike.
    unawaited(onboardingIntroService.markCompletedOnDevice());
    final currentUserId =
        authService.currentUser?.id ?? authService.currentAdmin?.id;
    setState(() {
      _loggedIn = true;
      _showSignUp = false;
      _isPreparingAccountPreferences = currentUserId != null;
    });
    unawaited(_finishLoginAfterTermsCheck(currentUserId));
  }

  /// Opens the read-only guest joyride from the landing screen's guest pill.
  ///
  /// Deliberately *not* routed through [_onLogin]: reaching an authenticated
  /// state there permanently retires the intro carousel on this device, and a
  /// visitor tapping "Guest Login" should not change what the device owner
  /// sees on their next launch.
  ///
  /// Order matters. `guestSession.begin()` closes every persistence and network
  /// gate, so it must happen before the seed world lands or any of it could
  /// reach disk.
  void _onGuestLogin() {
    guestSession.begin();
    // Identity before content, in that order. `enterGuestSession` crosses an
    // auth boundary, which tells ChatStore to drop the previous occupant's
    // cached conversations — seeding first would have that teardown wipe the
    // guest's own seeded chats straight back out.
    authService.enterGuestSession();
    seedGuestWorld();
    setState(() {
      _loggedIn = true;
      _showSignUp = false;
      _isPreparingAccountPreferences = false;
    });
  }

  bool get _termsPermitAuthenticatedAccess {
    return !termsAcceptanceService.hasAuthenticatedUser ||
        termsAcceptanceService.hasAcceptedCurrentTerms;
  }

  Future<void> _finishLoginAfterTermsCheck(String? currentUserId) async {
    if (termsAcceptanceService.hasAuthenticatedUser &&
        !termsAcceptanceService.isLoadedForCurrentUser) {
      await termsAcceptanceService.loadForCurrentUser();
    }
    if (!_termsPermitAuthenticatedAccess) {
      if (mounted) {
        setState(() => _isPreparingAccountPreferences = false);
      }
      return;
    }
    await _finishLogin(currentUserId);
  }

  Future<void> _acceptCurrentTerms() async {
    await termsAcceptanceService.acceptCurrentTerms();
    if (!mounted || !termsAcceptanceService.hasAcceptedCurrentTerms) return;
    setState(() => _isPreparingAccountPreferences = true);
    final currentUserId =
        authService.currentUser?.id ?? authService.currentAdmin?.id;
    await _finishLogin(currentUserId);
  }

  Future<void> _retryCurrentTermsCheck() async {
    await termsAcceptanceService.loadForCurrentUser();
    if (!mounted || !termsAcceptanceService.hasAcceptedCurrentTerms) return;
    setState(() => _isPreparingAccountPreferences = true);
    final currentUserId =
        authService.currentUser?.id ?? authService.currentAdmin?.id;
    await _finishLogin(currentUserId);
  }

  Future<void> _finishLogin(String? currentUserId) async {
    try {
      if (currentUserId != null) {
        await _loadAccountPreferences();
      }
      if (mounted) _activateAuthenticatedServices();
    } finally {
      // Every success, error, and timeout path must retire the launch spinner.
      if (mounted) {
        setState(() => _isPreparingAccountPreferences = false);
      }
    }
  }

  void _activateAuthenticatedServices() {
    if (!_termsPermitAuthenticatedAccess) return;
    // A guest has no backend account: nothing to register a push device for,
    // no preferences to load, and no follow graph to hydrate. The seed world
    // already supplied all of it.
    if (guestSession.isActive) return;
    final currentUserId =
        authService.currentUser?.id ?? authService.currentAdmin?.id;
    if (currentUserId != null) {
      authService.activateAcceptedSession();
      if (_firebaseReady) {
        unawaited(pushNotificationService.activateForCurrentUser());
      }
      unawaited(moderationService.activateForUser(currentUserId));
      unawaited(eventCleanupService.cleanupExpiredEvents());
      if (appBootstrap.localDataReady) {
        _prefsLoadedForUserId = currentUserId;
        userPrefsService.load(currentUserId);
        personalizationService.load(currentUserId);
        unawaited(peopleService.hydrateFollowing(currentUserId));
      }
    }
  }

  void _onSignUp(String email) {
    // Sign-up complete → return to the root Login Screen with the email
    // pre-filled so the student can log straight in.
    setState(() {
      _signupEmail = email;
      _showSignUp = false;
    });
  }

  // Custom back navigation from the sign-up flow → root Login Screen.
  void handleBack() {
    setState(() => _showSignUp = false);
  }

  Future<void> _dismissIntro({required bool showSignUp}) async {
    // Persist before changing destinations so killing the app immediately
    // after Skip/Get started still cannot replay the carousel next launch.
    await onboardingIntroService.markSeenOnDevice();
    if (!mounted) return;
    setState(() {
      _showIntroThisLaunch = false;
      _showSignUp = showSignUp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        themeService,
        localeService,
        accountPreferencesService,
        termsAcceptanceService,
      ]),
      builder: (context, _) {
        final isDark = themeService.isDark;
        Widget homeWidget;
        Widget Function()? sessionGateBuilder;
        String destinationKey;
        if (_isBootstrapping || _isCheckingForUpdate) {
          // Keep the branded launch screen up while the minimum-version check
          // is in flight. No authenticated or cached destination is exposed
          // before the check completes.
          homeWidget = const AppLaunchScreen();
          destinationKey = 'update-check';
        } else if (_requiredUpdate != null) {
          homeWidget = UpdateRequiredScreen(
            storeUrl: _requiredUpdate!.storeUrl,
            onRetry: _retryUpdateCheck,
          );
          destinationKey = 'update-required';
        } else if (_showIntroThisLaunch &&
            !_showSignUp &&
            !_loggedIn &&
            authService.currentUser == null &&
            authService.currentAdmin == null) {
          // Show the intro once after installation. Get started, Skip, and Log
          // in all persistently retire it before navigating away.
          homeWidget = OnboardingCarouselScreen(
            onGetStarted: () => unawaited(_dismissIntro(showSignUp: true)),
            onLogIn: () => unawaited(_dismissIntro(showSignUp: false)),
          );
          destinationKey = 'onboarding';
        } else if ((authService.currentUser != null ||
                authService.currentAdmin != null) &&
            termsAcceptanceService.hasAuthenticatedUser &&
            !termsAcceptanceService.hasAcceptedCurrentTerms) {
          if (termsAcceptanceService.status == TermsAcceptanceStatus.checking ||
              termsAcceptanceService.status ==
                  TermsAcceptanceStatus.signedOut) {
            homeWidget = const AppLaunchScreen();
            sessionGateBuilder = () => const AppLaunchScreen();
            destinationKey = 'terms-check';
          } else {
            Widget buildTermsGate() => TermsAcceptanceScreen(
              onAccepted: _acceptCurrentTerms,
              onRetryCheck: _retryCurrentTermsCheck,
              verificationFailed:
                  termsAcceptanceService.status == TermsAcceptanceStatus.error,
            );

            homeWidget = buildTermsGate();
            sessionGateBuilder = buildTermsGate;
            destinationKey = 'terms-acceptance';
          }
        } else if (_isPreparingAccountPreferences) {
          homeWidget = const AppLaunchScreen();
          destinationKey = 'account-preferences-loading';
        } else if (_loggedIn ||
            authService.currentUser != null ||
            authService.currentAdmin != null) {
          final isAdmin = isClubUpAdmin(authService.currentAdmin);
          final currentUserId =
              authService.currentUser?.id ?? authService.currentAdmin?.id;
          if (appBootstrap.localDataReady &&
              currentUserId != null &&
              currentUserId != _prefsLoadedForUserId) {
            _prefsLoadedForUserId = currentUserId;
            userPrefsService.load(currentUserId);
            personalizationService.load(currentUserId);
          }
          final requiredAccountPreference =
              accountPreferencesService.nextRequiredPreference;
          // The one-time language/theme pickers are per-account preferences
          // written to Hive. A guest has neither, so skip straight to the app
          // rather than making a visitor answer two setup questions first.
          final isGuest = guestSession.isActive;
          final needsLanguagePreference =
              accountPreferencesService.hasAuthenticatedUser
              ? requiredAccountPreference == AccountPreferencePrompt.language
              : currentUserId != null &&
                    !localeService.hasChosenLanguage(currentUserId);
          final needsThemePreference =
              accountPreferencesService.hasAuthenticatedUser
              ? requiredAccountPreference == AccountPreferencePrompt.theme
              : currentUserId != null &&
                    !themeService.hasChosenTheme(currentUserId);
          if (!isGuest && currentUserId != null && needsLanguagePreference) {
            homeWidget = LanguageChoiceScreen(
              onChoose: (code) =>
                  localeService.markLanguageChosen(currentUserId, code),
            );
            destinationKey = 'language-choice';
          } else if (!isGuest &&
              currentUserId != null &&
              needsThemePreference) {
            homeWidget = ThemeChoiceScreen(
              onChoose: (dark) =>
                  themeService.markThemeChosen(currentUserId, dark),
            );
            destinationKey = 'theme-choice';
          } else {
            homeWidget = MainNavScreen(
              isAdmin: isAdmin,
              onLogout: () {
                _savePrefs();
                moderationService.clearActiveUser();
                accountPreferencesService.clear();
                _prefsLoadedForUserId = null;
                setState(() {
                  _loggedIn = false;
                  _showSignUp = false;
                });
              },
            );
            destinationKey = 'main-navigation';
          }
        } else if (_showSignUp) {
          homeWidget = AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: SignupFlowScreen(onSignUp: _onSignUp, onBack: handleBack),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
          destinationKey = 'sign-up';
        } else {
          // Root entry: the Login Screen. "Sign up" hands off to the
          // multi-step sign-up flow; club-admin sign-in is reached from its
          // footer link.
          homeWidget = AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: LoginScreen(
              onLogin: _onLogin,
              onSignUp: () => setState(() => _showSignUp = true),
              onAdminLogin: _onLogin,
              onGuestLogin: _onGuestLogin,
              initialEmail: _signupEmail,
            ),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
          );
          destinationKey = 'login';
        }
        final isUsableDestination =
            !_isBootstrapping &&
            !_isCheckingForUpdate &&
            !_isLaunching &&
            destinationKey != 'terms-check' &&
            destinationKey != 'account-preferences-loading';
        if (isUsableDestination && !_didLogInitialRoute) {
          _didLogInitialRoute = true;
          StartupLog.event('S11_INITIAL_ROUTE', result: destinationKey);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            StartupLog.event('S12_FIRST_USABLE_FRAME', result: destinationKey);
          });
        }
        final visibleHome = AnimatedSwitcher(
          duration:
              sessionGateBuilder != null ||
                  widget.minimumLaunchDuration == Duration.zero
              ? Duration.zero
              : destinationKey == 'sign-up'
              ? const Duration(milliseconds: 1100)
              : const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOutQuint,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) {
            final isLaunchScreen =
                child.key == const ValueKey<String>('app-launch');
            if (isLaunchScreen) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.035, end: 1).animate(animation),
                  child: child,
                ),
              );
            }

            if (child.key ==
                const ValueKey<String>('app-destination-sign-up')) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.08, 1, curve: Curves.easeInOutCubic),
                ),
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0.045, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              );
            }

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(animation),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.99, end: 1).animate(animation),
                  child: child,
                ),
              ),
            );
          },
          child: _isLaunching
              ? const AppLaunchScreen(key: ValueKey('app-launch'))
              : KeyedSubtree(
                  key: ValueKey('app-destination-$destinationKey'),
                  child: homeWidget,
                ),
        );
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'ClubUp',
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: _lightTheme ??= AppTheme.build(AppThemeVariant.light),
          darkTheme: _darkTheme ??= AppTheme.build(AppThemeVariant.dark),
          highContrastTheme: _highContrastLightTheme ??= AppTheme.build(
            AppThemeVariant.highContrastLight,
          ),
          highContrastDarkTheme: _highContrastDarkTheme ??= AppTheme.build(
            AppThemeVariant.highContrastDark,
          ),
          locale: Locale(localeService.languageCode),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          scrollBehavior: const _ClubUpScrollBehavior(),
          builder: (context, child) {
            final navigator = child ?? const SizedBox.shrink();
            final sessionGate = sessionGateBuilder?.call();
            Widget content;
            if (sessionGate != null) {
              content = destinationKey == 'terms-check'
                  ? sessionGate
                  : _WebEntryFrame(child: sessionGate);
            } else if (_isLaunching || destinationKey == 'main-navigation') {
              content = navigator;
            } else {
              content = _WebEntryFrame(child: navigator);
            }
            return AppSystemUiOverlay(child: content);
          },
          home: visibleHome,
        );
      },
    );
  }
}

class _ClubUpScrollBehavior extends MaterialScrollBehavior {
  const _ClubUpScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

/// Gives the signed-out experience a focused, app-sized canvas on desktop web
/// while preserving the original edge-to-edge layout on phones and narrow
/// browser windows.
class _WebEntryFrame extends StatelessWidget {
  final Widget child;

  const _WebEntryFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) return child;

        const outerPadding = 24.0;
        final width = (constraints.maxWidth - outerPadding * 2)
            .clamp(0.0, 600.0)
            .toDouble();
        final height = (constraints.maxHeight - outerPadding * 2)
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        final media = MediaQuery.of(context);
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final semantic = context.semanticColors;
        final background = theme.scaffoldBackgroundColor;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            gradient: RadialGradient(
              center: const Alignment(-0.75, -0.8),
              radius: 1.5,
              colors: [
                semantic.brand.withValues(alpha: isDark ? 0.15 : 0.08),
                background,
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: background,
                borderRadius: const BorderRadius.all(Radius.circular(24)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.75),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
                    blurRadius: 42,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: MediaQuery(
                data: media.copyWith(size: Size(width, height)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
