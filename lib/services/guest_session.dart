import 'package:flutter/foundation.dart';

/// Marks the process as running the read-only guest joyride.
///
/// Guest mode shows the whole app against fabricated data and must leave no
/// trace: no Supabase call, no Hive row, no SharedPreferences key, no device
/// calendar entry, no push registration. Rather than growing a parallel set of
/// no-op services, guest mode reuses the degradation the app already performs
/// when Supabase is unconfigured — every `_client` getter in the service layer
/// also consults [isActive], and every persistence entry point returns early.
///
/// Two properties of this class are load-bearing:
///
/// * **It imports nothing from the service layer.** Services at every level
///   (including ones `supabase_config.dart`-adjacent) import it, so taking on
///   a dependency here would create an import cycle.
/// * **It is release-safe.** Guest login ships to real users, so it must not
///   be reachable only through `SupabaseConfig.canUseMockAuth`, which is
///   `false` in release builds.
///
/// Callers must flip the flag *before* mutating anything, so the persistence
/// gates are already closed by the time seed data lands.
class GuestSession extends ChangeNotifier {
  bool _active = false;

  /// True while the guest joyride owns the session.
  bool get isActive => _active;

  void begin() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// Process-lifetime singleton. Like the other service singletons in this
/// codebase it is never disposed.
final guestSession = GuestSession();
