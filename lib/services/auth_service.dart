import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart'
    as supabase_auth
    show User;

import '../models/user.dart';
import '../models/app_admin.dart';
import 'mock_data.dart';
import 'mock_clubup_profile.dart';
import 'club_follow_service.dart';
import 'rsvp_store.dart';
import 'student_profile_service.dart';
import 'supabase_interaction_service.dart';
import 'supabase_config.dart';
import 'push_notification_service.dart';
import 'auth_session_store.dart';
import 'user_state.dart';
import 'lazy_content_loader.dart';
import 'people_service.dart';
import 'terms_acceptance_service.dart';
import 'admin_moderation_service.dart';
import 'platform_admin_auth_service.dart';
import 'session_restoration.dart';
import 'supabase_content_service.dart';
import 'guest_session.dart';
import 'guest_world.dart';

enum AuthLoginFailure { none, invalidCredentials, banned }

class AuthService {
  AuthService({
    AdminModerationService? moderationService,
    Duration sessionRestorationTimeout = const Duration(seconds: 8),
  }) : _moderationService = moderationService ?? adminModerationService,
       _sessionRestorationTimeout = sessionRestorationTimeout;

  final AdminModerationService _moderationService;
  final Duration _sessionRestorationTimeout;
  User? _currentUser;
  AppAdmin? _currentAdmin;
  Map<String, dynamic>? _pendingStudentProfileRow;
  String? _activatedStudentUserId;
  int _studentHydrationGeneration = 0;
  int _sessionRestorationGeneration = 0;
  void Function()? _chatAuthBoundaryHandler;

  User? get currentUser => _currentUser;
  AppAdmin? get currentAdmin => _currentAdmin;
  AuthLoginFailure lastLoginFailure = AuthLoginFailure.none;
  SessionRestorationResult lastSessionRestorationResult =
      SessionRestorationResult.noSavedSession;

  bool get isStudentSession =>
      _currentAdmin == null &&
      _currentUser != null &&
      _currentUser!.role == 'student';

  /// ChatStore registers a synchronous auth-boundary hook so cached v2
  /// summaries/messages are cleared before another account can render.
  void registerChatAuthBoundary(void Function() handler) {
    _chatAuthBoundaryHandler = handler;
  }

  void _invalidateChatAuthBoundary() {
    _chatAuthBoundaryHandler?.call();
  }

  /// Signs the fabricated guest profile in for the read-only joyride.
  ///
  /// The guest is deliberately shaped as an ordinary *student* session
  /// (`role: 'student'`, no [currentAdmin]) because roughly forty write
  /// affordances across the app — liking, RSVPing, commenting, following
  /// people, saved items, the Search tab — are gated on [isStudentSession].
  /// Any other role would render the tour read-only.
  ///
  /// Unlike the real login paths this performs no network call and starts no
  /// device session clock: the caller has already set `guestSession.begin()`,
  /// so `authSessionStore`, Hive and Supabase are all closed for business.
  void enterGuestSession() {
    _studentHydrationGeneration++;
    userState.setFollowedClubsLoading(false);
    _invalidateChatAuthBoundary();
    _currentAdmin = null;
    _currentUser = guestSessionUser();
    _pendingStudentProfileRow = null;
    _activatedStudentUserId = null;
    // No terms check: there is no authenticated Supabase user to record an
    // acceptance against, and the gate keys off exactly that.
  }

  void setClubAdmin(AppAdmin admin, {bool checkTerms = true}) {
    _studentHydrationGeneration++;
    userState.setFollowedClubsLoading(false);
    _invalidateChatAuthBoundary();
    lazyContentLoader.invalidate();
    if (isClubUpMockAdmin(admin)) {
      ensureClubUpMockProfile();
    } else {
      ensureClubForAdmin(admin);
    }
    if (admin.isPlatformAdmin) appAdmin = admin;
    _currentAdmin = admin;
    _currentUser = null;
    _pendingStudentProfileRow = null;
    _activatedStudentUserId = null;
    if (checkTerms) _startTermsAcceptanceCheck();
  }

  void _startTermsAcceptanceCheck() {
    unawaited(termsAcceptanceService.loadForCurrentUser());
  }

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  bool hasNoAdjacentRepeatedDigits(String password) {
    for (var i = 1; i < password.length; i++) {
      if (password.codeUnitAt(i) == password.codeUnitAt(i - 1)) {
        return false;
      }
    }
    return true;
  }

  bool hasNoAdjacentSequentialDigits(String password) {
    for (var i = 1; i < password.length; i++) {
      final current = password.codeUnitAt(i);
      final previous = password.codeUnitAt(i - 1);
      if ((current - previous).abs() == 1) {
        return false;
      }
    }
    return true;
  }

  bool isValidStudentPassword(String password) {
    return password.length == 6 && _digitsOnly.hasMatch(password);
  }

  bool isValidNewStudentPassword(String password) {
    return password.length == 6 &&
        _digitsOnly.hasMatch(password) &&
        hasNoAdjacentRepeatedDigits(password) &&
        hasNoAdjacentSequentialDigits(password);
  }

  bool isValidClubPassword(String password) {
    return password.length == 8 && _digitsOnly.hasMatch(password);
  }

  bool isValidNumericPassword(String password) {
    return isValidNewStudentPassword(password);
  }

  bool login(String email, String password) {
    lastLoginFailure = AuthLoginFailure.none;
    final normalizedEmail = email.trim().toLowerCase();
    if (SupabaseConfig.canUseMockAuth &&
        normalizedEmail == clubUpMockEmail &&
        password == clubUpMockPasscode) {
      ensureClubUpMockProfile();
    }
    if (appAdmin.id.isNotEmpty &&
        normalizedEmail == appAdmin.email.toLowerCase() &&
        appAdmin.password == password) {
      _invalidateChatAuthBoundary();
      _currentAdmin = appAdmin;
      _currentUser = null;
      _pendingStudentProfileRow = null;
      _activatedStudentUserId = null;
      return true;
    }
    final clubAdmin = clubAdmins.firstWhere(
      (a) => a.email.toLowerCase() == normalizedEmail && a.password == password,
      orElse: () => AppAdmin(id: '', name: '', email: '', password: ''),
    );
    if (clubAdmin.id.isNotEmpty) {
      if (_moderationService.isClubBannedCached(
        clubId: clubAdmin.id,
        email: clubAdmin.email,
      )) {
        lastLoginFailure = AuthLoginFailure.banned;
        return false;
      }
      _invalidateChatAuthBoundary();
      _currentAdmin = clubAdmin;
      _currentUser = null;
      _pendingStudentProfileRow = null;
      _activatedStudentUserId = null;
      return true;
    }
    final user = users.firstWhere(
      (u) => u.email.toLowerCase() == normalizedEmail && u.password == password,
      orElse: () => User(
        id: '',
        name: '',
        email: '',
        password: '',
        role: '',
        subscribedClubIds: [],
      ),
    );
    if (user.id.isNotEmpty) {
      if (_moderationService.isUserBannedCached(
        userId: user.id,
        email: user.email,
      )) {
        lastLoginFailure = AuthLoginFailure.banned;
        return false;
      }
      _invalidateChatAuthBoundary();
      _currentUser = user;
      _currentAdmin = null;
      _pendingStudentProfileRow = null;
      _activatedStudentUserId = null;
      return true;
    }
    lastLoginFailure = AuthLoginFailure.invalidCredentials;
    return false;
  }

  Future<bool> loginStudent(String email, String password) async {
    lastLoginFailure = AuthLoginFailure.none;
    final normalizedEmail = email.trim().toLowerCase();

    final isMockAdmin =
        (appAdmin.id.isNotEmpty &&
            appAdmin.email.toLowerCase() == normalizedEmail) ||
        clubAdmins.any((a) => a.email.toLowerCase() == normalizedEmail) ||
        (SupabaseConfig.canUseMockAuth && normalizedEmail == clubUpMockEmail);
    if (SupabaseConfig.canUseMockAuth && isMockAdmin) {
      return isValidClubPassword(password) && login(email, password);
    }

    if (!isValidStudentPassword(password)) {
      lastLoginFailure = AuthLoginFailure.invalidCredentials;
      return false;
    }
    if (SupabaseConfig.canUseMockAuth &&
        users.any(
          (user) =>
              user.email.toLowerCase() == normalizedEmail &&
              user.password == password,
        )) {
      return login(email, password);
    }

    if (SupabaseConfig.isConfigured) {
      try {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        );
        final authUser = response.user;
        if (authUser == null) {
          lastLoginFailure = AuthLoginFailure.invalidCredentials;
          return false;
        }
        if (await _moderationService.isUserBanned(
          userId: authUser.id,
          email: authUser.email ?? normalizedEmail,
        )) {
          await Supabase.instance.client.auth.signOut();
          lastLoginFailure = AuthLoginFailure.banned;
          return false;
        }
        _invalidateChatAuthBoundary();
        await authSessionStore.startNewSession();
        lazyContentLoader.invalidate();

        // Login first loads only the core `profiles` row needed to identify
        // the account. All protected account hydration waits for the root
        // Terms gate to grant this session access.
        Map<String, dynamic>? profileRow;
        try {
          profileRow = await studentProfileService.fetchProfileCore(
            authUser.id,
          );
        } catch (_) {
          profileRow = null;
        }

        String? rowString(String key) {
          final text = profileRow?[key]?.toString().trim() ?? '';
          return text.isEmpty ? null : text;
        }

        _currentUser = User(
          id: authUser.id,
          name:
              rowString('full_name') ??
              (authUser.userMetadata?['full_name'] as String?) ??
              normalizedEmail,
          email: rowString('email') ?? normalizedEmail,
          password: '',
          role: rowString('role') ?? 'student',
          subscribedClubIds: const [],
        );
        unawaited(peopleService.registerLocalUser(_currentUser!));
        _currentAdmin = null;
        _pendingStudentProfileRow = profileRow;
        _activatedStudentUserId = null;
        if (profileRow != null) {
          studentProfileService.applyCoreToUserState(profileRow);
        }
        // Authentication succeeds even when this read fails, but the
        // account remains behind the fail-closed root Terms gate.
        await termsAcceptanceService.loadForCurrentUser();
        return true;
      } on AuthException {
        lastLoginFailure = AuthLoginFailure.invalidCredentials;
        return false;
      } catch (_) {
        lastLoginFailure = AuthLoginFailure.invalidCredentials;
        return false;
      }
    }

    final loggedIn = SupabaseConfig.canUseMockAuth && login(email, password);
    if (!loggedIn && lastLoginFailure == AuthLoginFailure.none) {
      lastLoginFailure = AuthLoginFailure.invalidCredentials;
    }
    return loggedIn;
  }

  /// Rebuilds the app's in-memory account from Supabase's persisted session.
  ///
  /// Supabase Flutter restores the access/refresh token pair during
  /// [Supabase.initialize]. The app still needs to reconstruct [_currentUser]
  /// or [_currentAdmin], otherwise the root router incorrectly shows Login.
  Future<bool> restorePersistedSession() async {
    if (!SupabaseConfig.isConfigured) return false;
    final restorationGeneration = ++_sessionRestorationGeneration;
    bool isCurrentRestoration() =>
        restorationGeneration == _sessionRestorationGeneration;
    final client = Supabase.instance.client;
    final runner = SessionRestorationRunner(
      timeout: _sessionRestorationTimeout,
      operations: SessionRestorationOperations(
        cachedSession: () async => _cachedIdentity(client.auth.currentSession),
        isDeviceSessionActive: authSessionStore.isSessionActive,
        refreshSession: () async {
          try {
            final response = await client.auth.refreshSession();
            return _cachedIdentity(response.session);
          } on AuthRetryableFetchException {
            rethrow;
          } on AuthException {
            throw const InvalidPersistedSession();
          }
        },
        loadPlatformAdminEmail: (userId) async {
          final rows =
              await client
                      .from('app_admins')
                      .select('auth_user_id, email')
                      .eq('auth_user_id', userId)
                      .limit(1)
                  as List;
          if (rows.isEmpty) return null;
          final email = (rows.first as Map)['email']?.toString().trim() ?? '';
          if (email.toLowerCase() != platformAdminEmail) {
            throw const InvalidPersistedSession();
          }
          return email;
        },
        loadClubId: (userId) async {
          final rows =
              await client
                      .from('club_auth_accounts')
                      .select('club_id')
                      .eq('auth_user_id', userId)
                      .limit(1)
                  as List;
          if (rows.isEmpty) return null;
          final id = (rows.first as Map)['club_id']?.toString() ?? '';
          if (id.isEmpty) throw const InvalidPersistedSession();
          return id;
        },
        loadClub: (clubId) async {
          final rows =
              await client
                      .from('clubs')
                      .select('id, name, email')
                      .eq('id', clubId)
                      .limit(1)
                  as List;
          if (rows.isEmpty) return null;
          final row = rows.first as Map;
          return RestoredClubIdentity(
            id: clubId,
            name: row['name']?.toString() ?? '',
            email: row['email']?.toString() ?? '',
          );
        },
        isClubBanned: (club) =>
            _moderationService.isClubBanned(clubId: club.id, email: club.email),
        isUserBanned: (identity) => _moderationService.isUserBanned(
          userId: identity.userId,
          email: identity.email,
        ),
        restorePlatformAdmin: (identity) async {
          if (!isCurrentRestoration()) return;
          setClubAdmin(
            AppAdmin(
              id: identity.userId,
              name: 'ClubUp Admin',
              email: platformAdminEmail,
              password: '',
              isPlatformAdmin: true,
            ),
            checkTerms: false,
          );
          await termsAcceptanceService.loadForCurrentUser();
        },
        restoreClubAdmin: (club) async {
          if (!isCurrentRestoration()) return;
          setClubAdmin(
            AppAdmin(
              id: club.id,
              name: club.name,
              email: club.email,
              password: '',
            ),
            checkTerms: false,
          );
          try {
            await supabaseContentService.fetchClubById(club.id);
          } catch (_) {
            // The authenticated club stub created by setClubAdmin is enough
            // to keep routing safe if the detail hydration is unavailable.
          }
          await termsAcceptanceService.loadForCurrentUser();
        },
        restoreStudent: (identity) => _setStudentFromIdentity(
          identity,
          isCurrentRestoration: isCurrentRestoration,
        ),
        clearInvalidSession: () => _clearPersistedSession(client),
      ),
    );
    lastSessionRestorationResult = await runner.restore();
    if (isCurrentRestoration()) _sessionRestorationGeneration++;
    return lastSessionRestorationResult == SessionRestorationResult.restored;
  }

  CachedSessionIdentity? _cachedIdentity(Session? session) {
    final user = session?.user;
    if (session == null || user == null) return null;
    return CachedSessionIdentity(
      userId: user.id,
      email: user.email,
      isExpired: session.isExpired,
    );
  }

  Future<void> _setStudentFromIdentity(
    CachedSessionIdentity identity, {
    required bool Function() isCurrentRestoration,
  }) async {
    final clientUser = Supabase.instance.client.auth.currentUser;
    if (clientUser == null || clientUser.id != identity.userId) {
      throw const InvalidPersistedSession();
    }
    await _setStudentFromAuthUser(
      clientUser,
      isCurrentRestoration: isCurrentRestoration,
    );
  }

  Future<void> _setStudentFromAuthUser(
    supabase_auth.User authUser, {
    bool Function()? isCurrentRestoration,
  }) async {
    _invalidateChatAuthBoundary();
    lazyContentLoader.invalidate();
    Map<String, dynamic>? profileRow;
    try {
      profileRow = await studentProfileService.fetchProfileCore(authUser.id);
    } catch (_) {
      profileRow = null;
    }
    if (isCurrentRestoration != null && !isCurrentRestoration()) return;

    String? rowString(String key) {
      final text = profileRow?[key]?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final email = rowString('email') ?? authUser.email?.toString() ?? '';
    _currentUser = User(
      id: authUser.id.toString(),
      name:
          rowString('full_name') ??
          (authUser.userMetadata?['full_name'] as String?) ??
          email,
      email: email,
      password: '',
      role: rowString('role') ?? 'student',
      subscribedClubIds: const [],
    );
    _currentAdmin = null;
    _pendingStudentProfileRow = profileRow;
    _activatedStudentUserId = null;
    unawaited(peopleService.registerLocalUser(_currentUser!));
    if (profileRow != null) {
      studentProfileService.applyCoreToUserState(profileRow);
    }
    await termsAcceptanceService.loadForCurrentUser();
  }

  /// Starts account data hydration only after the root Terms gate grants the
  /// authenticated session access. Repeated router/lifecycle calls are safe.
  void activateAcceptedSession() {
    final user = _currentUser;
    if (user == null || _activatedStudentUserId == user.id) return;
    if (termsAcceptanceService.hasAuthenticatedUser &&
        !termsAcceptanceService.hasAcceptedCurrentTerms) {
      return;
    }

    _activatedStudentUserId = user.id;
    final hydrationGeneration = ++_studentHydrationGeneration;
    userState.setFollowedClubsLoading(true);
    final profileRow = _pendingStudentProfileRow;
    if (profileRow != null) {
      unawaited(studentProfileService.hydrateDetails(profileRow));
    }
    unawaited(_hydrateStudentState(user.id, hydrationGeneration));
  }

  Future<void> _clearPersistedSession([SupabaseClient? client]) async {
    _studentHydrationGeneration++;
    userState.setFollowedClubsLoading(false);
    _invalidateChatAuthBoundary();
    _currentUser = null;
    _currentAdmin = null;
    _pendingStudentProfileRow = null;
    _activatedStudentUserId = null;
    _clearPlatformAdminIdentity();
    termsAcceptanceService.clear();
    try {
      await authSessionStore.clear();
    } catch (_) {
      // Local Supabase token deletion must still run if prefs are unavailable.
    }
    try {
      await (client ?? Supabase.instance.client).auth.signOut();
    } catch (_) {
      // signOut removes the local session before attempting server revocation.
    }
  }

  Future<Set<String>?> _tryHydrateSet(Future<Set<String>> request) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return await request;
    } catch (_) {
      // A failed refresh must not erase a valid local snapshot.
      return null;
    }
  }

  Future<void> _hydrateStudentState(
    String userId,
    int hydrationGeneration,
  ) async {
    final followedClubRevision = clubFollowService.followedClubRevisionFor(
      userId,
    );
    final followedClubFuture = _tryHydrateSet(
      clubFollowService.fetchFollowedClubIds(userId),
    );
    final likedPostFuture = _tryHydrateSet(
      supabaseInteractionService.fetchLikedPostIds(userId),
    );
    final rsvpEventFuture = _tryHydrateSet(
      supabaseInteractionService.fetchRsvpEventIds(userId),
    );

    try {
      // Apply followed clubs as soon as their own request finishes. They
      // must not wait for unrelated likes or RSVP hydration.
      final followedClubIds = await followedClubFuture;
      if (_isCurrentStudentHydration(
        userId,
        hydrationGeneration,
        followedClubRevision,
      )) {
        if (followedClubIds != null) {
          userState.replaceFollowedClubs(followedClubIds);
          for (final clubId in followedClubIds) {
            final current = supabaseClubMemberCounts[clubId] ?? 0;
            if (current < 1) supabaseClubMemberCounts[clubId] = 1;
          }
        }
        userState.setFollowedClubsLoading(false);
      }

      final userStateResults = await Future.wait<Set<String>?>([
        likedPostFuture,
        rsvpEventFuture,
      ]);
      if (!_isCurrentStudentHydration(
        userId,
        hydrationGeneration,
        followedClubRevision,
      )) {
        return;
      }

      final likedPostIds = userStateResults[0];
      if (likedPostIds != null) userState.replaceLikedPosts(likedPostIds);

      final rsvpEventIds = userStateResults[1];
      if (rsvpEventIds != null) rsvpStore.replaceForUser(rsvpEventIds, userId);
    } finally {
      if (_isCurrentStudentHydration(
        userId,
        hydrationGeneration,
        followedClubRevision,
      )) {
        userState.setFollowedClubsLoading(false);
      }
    }
  }

  bool _isCurrentStudentHydration(
    String userId,
    int hydrationGeneration,
    int followedClubRevision,
  ) {
    return hydrationGeneration == _studentHydrationGeneration &&
        _currentUser?.id == userId &&
        clubFollowService.followedClubRevisionFor(userId) ==
            followedClubRevision;
  }

  bool signUp(String name, String email, String password) {
    if (users.any((u) => u.email == email)) {
      return false;
    }
    if (!isValidNumericPassword(password)) {
      return false;
    }
    final newUser = User(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      email: email,
      password: password,
      role: 'student',
      subscribedClubIds: [],
    );
    users.add(newUser);
    unawaited(peopleService.registerLocalUser(newUser));
    _currentUser = newUser;
    _currentAdmin = null;
    _pendingStudentProfileRow = null;
    _activatedStudentUserId = null;
    return true;
  }

  bool hasAccountEmail(String email) {
    final normalized = email.toLowerCase();
    return users.any((u) => u.email.toLowerCase() == normalized) ||
        appAdmin.email.toLowerCase() == normalized ||
        clubAdmins.any((a) => a.email.toLowerCase() == normalized);
  }

  bool resetAccountPassword(String email, String newPassword) {
    final normalized = email.toLowerCase();
    final index = users.indexWhere((u) => u.email.toLowerCase() == normalized);
    if (index >= 0) {
      if (!isValidNewStudentPassword(newPassword)) return false;
      final user = users[index];
      users[index] = User(
        id: user.id,
        name: user.name,
        email: user.email,
        password: newPassword,
        role: user.role,
        subscribedClubIds: user.subscribedClubIds,
        followingUserIds: user.followingUserIds,
      );
      if (_currentUser?.id == user.id) {
        _currentUser = users[index];
      }
      return true;
    }

    if (appAdmin.email.toLowerCase() == normalized) {
      if (!isValidClubPassword(newPassword)) return false;
      appAdmin = AppAdmin(
        id: appAdmin.id,
        name: appAdmin.name,
        email: appAdmin.email,
        password: newPassword,
        isPlatformAdmin: appAdmin.isPlatformAdmin,
      );
      if (_currentAdmin?.id == appAdmin.id) {
        _currentAdmin = appAdmin;
      }
      return true;
    }

    final adminIndex = clubAdmins.indexWhere(
      (a) => a.email.toLowerCase() == normalized,
    );
    if (adminIndex >= 0) {
      if (!isValidClubPassword(newPassword)) return false;
      final admin = clubAdmins[adminIndex];
      clubAdmins[adminIndex] = AppAdmin(
        id: admin.id,
        name: admin.name,
        email: admin.email,
        password: newPassword,
        isPlatformAdmin: admin.isPlatformAdmin,
      );
      if (_currentAdmin?.id == admin.id) {
        _currentAdmin = clubAdmins[adminIndex];
      }
      return true;
    }

    return false;
  }

  void updateCurrentUserName(String name) {
    final user = _currentUser;
    if (user == null) return;

    _currentUser = User(
      id: user.id,
      name: name,
      email: user.email,
      password: user.password,
      role: user.role,
      subscribedClubIds: user.subscribedClubIds,
      followingUserIds: user.followingUserIds,
    );

    final index = users.indexWhere((u) => u.id == user.id);
    if (index >= 0) {
      final existing = users[index];
      users[index] = User(
        id: existing.id,
        name: name,
        email: existing.email,
        password: existing.password,
        role: existing.role,
        subscribedClubIds: existing.subscribedClubIds,
        followingUserIds: existing.followingUserIds,
      );
    }
  }

  Future<void> logout() async {
    _studentHydrationGeneration++;
    userState.setFollowedClubsLoading(false);
    _invalidateChatAuthBoundary();

    // The guest joyride has no Supabase session, no device session clock and
    // no registered push device, so none of the remote teardown below applies.
    // Tearing the fabricated world down while `guestSession` is still active
    // is what keeps the emptying itself off disk; the flag drops last.
    if (guestSession.isActive) {
      _currentUser = null;
      _currentAdmin = null;
      _pendingStudentProfileRow = null;
      _activatedStudentUserId = null;
      termsAcceptanceService.clear();
      clearGuestWorld();
      guestSession.end();
      lazyContentLoader.invalidate();
      return;
    }

    final wasClubUpMockSession = isClubUpMockAdmin(_currentAdmin);
    lazyContentLoader.invalidate();
    _currentUser = null;
    _currentAdmin = null;
    _pendingStudentProfileRow = null;
    _activatedStudentUserId = null;
    _clearPlatformAdminIdentity();
    termsAcceptanceService.clear();
    if (wasClubUpMockSession) removeClubUpMockProfile();

    try {
      await authSessionStore.clear();
    } catch (_) {
      // Token deletion below must still run if preferences are unavailable.
    }
    if (SupabaseConfig.isConfigured) {
      try {
        await pushNotificationService.deactivateCurrentUser();
      } catch (_) {
        // Device cleanup must never prevent local credential deletion.
      }
      try {
        // signOut removes the persisted local token before attempting remote
        // revocation, so logout remains reliable while offline.
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // Tests may exercise logout without bootstrapping Supabase.
      }
    }
  }

  void _clearPlatformAdminIdentity() {
    if (!appAdmin.isPlatformAdmin) return;
    appAdmin = AppAdmin(id: '', name: '', email: '', password: '');
  }
}

final authService = AuthService();
