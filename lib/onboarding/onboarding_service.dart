import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_config.dart';
import '../services/guest_session.dart';

typedef TutorialCompletionLoader = Future<bool?> Function(String profileId);
typedef TutorialCompletionWriter = Future<void> Function(String profileId);

/// Why the existing tutorial is currently being shown.
///
/// Only [automatic] runs are allowed to persist first-time completion.
enum TutorialLaunchSource { automatic, manual }

/// Tracks whether a user has been through the first-run "campus tour"
/// onboarding, and carries the replay / deep-link signals the flow needs.
///
/// Completion lives in
/// `public.user_preferences.has_completed_tutorial`, keyed by the authenticated
/// Supabase account. That account key covers student profiles and club-account
/// profiles even though the app-facing id for a club session is the club id.
/// SharedPreferences is used only by offline/mock sessions with no backend.
class OnboardingService {
  OnboardingService({
    TutorialCompletionLoader? completionLoader,
    TutorialCompletionWriter? completionWriter,
  }) : _completionLoader = completionLoader,
       _completionWriter = completionWriter;

  static const String _completionPrefix = 'has_completed_tutorial_';
  static const String _table = 'user_preferences';
  static const String _column = 'has_completed_tutorial';

  final TutorialCompletionLoader? _completionLoader;
  final TutorialCompletionWriter? _completionWriter;

  SharedPreferences? _preferences;

  /// Server-backed completion state, keyed by the id [isComplete] is asked
  /// about. Populated by [loadFor] before the tour decision is made.
  final Map<String, bool> _completion = <String, bool>{};

  /// Incremented when Settings asks for the tour to run again.
  final ValueNotifier<int> replayRequests = ValueNotifier<int>(0);

  /// Set to a bottom-nav index when the starter checklist (or the finish
  /// view) wants MainNavScreen to jump to a tab.
  final ValueNotifier<int?> tabRequests = ValueNotifier<int?>(null);

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  /// Reads completion from Supabase into memory before the automatic tutorial
  /// decision is made. A missing/null field is safely treated as incomplete;
  /// a failed backend read is unknown and therefore fails closed (complete).
  Future<void> loadFor(String profileId) async {
    if (profileId.isEmpty) return;

    final injectedLoader = _completionLoader;
    if (injectedLoader != null) {
      try {
        _completion[profileId] = await injectedLoader(profileId) ?? false;
      } catch (_) {
        _completion[profileId] = true;
      }
      return;
    }

    final client = _client;
    final authUserId = client?.auth.currentUser?.id;
    if (client == null || authUserId == null) {
      // Offline/mock app sessions have no account-level source of truth. Keep
      // an explicit test/demo override, otherwise suppress automatic launch.
      _completion.putIfAbsent(profileId, () => true);
      return;
    }

    try {
      final row = await client
          .from(_table)
          .select(_column)
          .eq('user_id', authUserId)
          .maybeSingle();
      _completion[profileId] = row?[_column] == true;
    } catch (_) {
      _completion[profileId] = true;
    }
  }

  bool isComplete(String profileId) {
    if (profileId.isEmpty) return true;
    final loaded = _completion[profileId];
    if (loaded != null) return loaded;
    // A configured backend must be loaded before a first-time decision. Never
    // infer remote state from device storage.
    if (_completionLoader != null || _client?.auth.currentUser != null) {
      return true;
    }
    return _mockCompletion(profileId);
  }

  /// Finishes a tutorial run without letting a Settings replay mutate the
  /// account's first-time completion field.
  Future<void> finish(
    String profileId, {
    required TutorialLaunchSource source,
  }) async {
    if (source == TutorialLaunchSource.manual) return;
    await complete(profileId);
  }

  /// Persists completion for an automatic first-time run.
  ///
  /// Backend writes happen before in-memory state changes so a failed write
  /// cannot masquerade as durable cross-device completion.
  Future<void> complete(String profileId) async {
    if (profileId.isEmpty) return;
    // The guest tour must not retire the tutorial for whoever owns the device.
    // (The auto-run passes TutorialLaunchSource.manual, which `finish` already
    // filters out; this is the belt to that braces.)
    if (guestSession.isActive) return;

    final injectedWriter = _completionWriter;
    if (injectedWriter != null) {
      await injectedWriter(profileId);
    } else {
      final client = _client;
      final authUserId = client?.auth.currentUser?.id;
      if (client != null && authUserId != null) {
        await client.from(_table).upsert({
          'user_id': authUserId,
          _column: true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      } else if (client != null) {
        throw StateError(
          'An authenticated Supabase user is required to complete tutorial.',
        );
      } else {
        await _preferences?.setBool('$_completionPrefix$profileId', true);
      }
    }
    _completion[profileId] = true;
  }

  /// Test/demo-only reset. It intentionally never writes `false` remotely.
  @visibleForTesting
  Future<void> reset(String profileId) async {
    if (profileId.isEmpty) return;
    _completion[profileId] = false;
    if (_completionLoader == null && _client == null) {
      await _preferences?.remove('$_completionPrefix$profileId');
    }
  }

  void requestReplay() {
    replayRequests.value++;
  }

  void requestTab(int index) {
    tabRequests.value = null; // re-fire even for the same tab twice in a row
    tabRequests.value = index;
  }

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool _mockCompletion(String profileId) {
    return _preferences?.getBool('$_completionPrefix$profileId') ?? false;
  }
}

final onboardingService = OnboardingService();
