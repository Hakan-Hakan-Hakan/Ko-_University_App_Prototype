import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'account_preferences_service.dart';
import 'guest_session.dart';

class ThemeService extends ChangeNotifier {
  ThemeService({
    Future<void> Function(bool)? accountSaver,
    String? Function()? accountIdProvider,
  }) : _accountSaver = accountSaver,
       _accountIdProvider = accountIdProvider;

  static const _boxName = 'theme_box';
  final Future<void> Function(bool)? _accountSaver;
  final String? Function()? _accountIdProvider;
  Box<dynamic>? _box;
  // First-time users always start in light; returning users keep their choice.
  bool _isDark = false;
  final Set<String> _themedUsers = {};
  final Map<String, bool> _themeByUser = {};

  bool get isDark => _isDark;

  Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    _isDark = _box!.get('isDark', defaultValue: false) as bool;
    final stored = _box!.get('themedUsers');
    if (stored != null) {
      _themedUsers.addAll(List<String>.from(stored as List));
    }
    final storedByUser = _box!.get('themeByUser');
    if (storedByUser is Map) {
      for (final entry in storedByUser.entries) {
        final userId = entry.key?.toString() ?? '';
        final dark = entry.value;
        if (userId.isNotEmpty && dark is bool) {
          _themeByUser[userId] = dark;
          _themedUsers.add(userId);
        }
      }
    }
  }

  /// Whether [userId] has already picked a theme (so we don't ask again).
  bool hasChosenTheme(String userId) => _themedUsers.contains(userId);

  bool? cachedThemeFor(String userId) => _themeByUser[userId];

  /// Guest sessions may flip this preference for the duration of the joyride,
  /// but must not overwrite what the device owner chose.
  Future<void> _persist(String key, Object? value) async {
    if (guestSession.isActive) return;
    await _box?.put(key, value);
  }

  Future<void> setDark(
    bool value, {
    bool persistToAccount = true,
    bool rethrowAccountSaveFailure = false,
  }) async {
    final changed = _isDark != value;
    _isDark = value;
    await _persist('isDark', value);
    if (persistToAccount) {
      final accountId = _accountIdProvider?.call();
      if (accountId != null && accountId.isNotEmpty) {
        await _cacheTheme(accountId, value);
      }
    }
    if (changed) notifyListeners();
    if (persistToAccount) {
      try {
        await _accountSaver?.call(value);
      } catch (_) {
        // Keep the device preference available while offline. A later change
        // in Settings will retry the account write.
        if (rethrowAccountSaveFailure) rethrow;
      }
    }
  }

  /// Records [userId]'s explicit light/dark choice and applies it.
  Future<void> markThemeChosen(String userId, bool dark) async {
    _isDark = dark;
    await _accountSaver?.call(dark);
    await _cacheTheme(userId, dark);
    final accountId = _accountIdProvider?.call();
    if (accountId != null && accountId.isNotEmpty && accountId != userId) {
      await _cacheTheme(accountId, dark);
    }
    await _persist('isDark', dark);
    notifyListeners();
  }

  Future<void> applyAccountTheme(String userId, bool dark) async {
    final changed = _isDark != dark;
    _isDark = dark;
    await _cacheTheme(userId, dark);
    await _persist('isDark', dark);
    if (changed) notifyListeners();
  }

  Future<void> _cacheTheme(String userId, bool dark) async {
    _themeByUser[userId] = dark;
    _themedUsers.add(userId);
    await _persist('themeByUser', Map<String, bool>.from(_themeByUser));
    await _persist('themedUsers', _themedUsers.toList());
  }
}

final themeService = ThemeService(
  accountSaver: accountPreferencesService.saveTheme,
  accountIdProvider: () => accountPreferencesService.authenticatedUserId,
);
