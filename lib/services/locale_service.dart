import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'account_preferences_service.dart';
import 'guest_session.dart';

class LocaleService extends ChangeNotifier {
  LocaleService({
    Future<void> Function(String)? accountSaver,
    String? Function()? accountIdProvider,
  }) : _accountSaver = accountSaver,
       _accountIdProvider = accountIdProvider;

  static const _boxName = 'locale_box';
  final Future<void> Function(String)? _accountSaver;
  final String? Function()? _accountIdProvider;
  static const defaultLanguageCode = 'tr';
  Box<dynamic>? _box;
  String _languageCode = defaultLanguageCode;
  final Set<String> _chosenLanguageUsers = {};
  final Map<String, String> _languageByUser = {};

  String get languageCode => _languageCode;

  Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    final storedLanguage = _box!.get('languageCode');
    _languageCode = storedLanguage == 'en' || storedLanguage == 'tr'
        ? storedLanguage as String
        : defaultLanguageCode;
    final stored = _box!.get('chosenLanguageUsers');
    if (stored != null) {
      _chosenLanguageUsers.addAll(List<String>.from(stored as List));
    }
    final storedByUser = _box!.get('languageByUser');
    if (storedByUser is Map) {
      for (final entry in storedByUser.entries) {
        final userId = entry.key?.toString() ?? '';
        final code = entry.value?.toString() ?? '';
        if (userId.isNotEmpty && _isSupported(code)) {
          _languageByUser[userId] = code;
          _chosenLanguageUsers.add(userId);
        }
      }
    }
  }

  bool hasChosenLanguage(String userId) =>
      _chosenLanguageUsers.contains(userId);

  String? cachedLanguageFor(String userId) => _languageByUser[userId];

  /// Guest sessions may flip this preference for the duration of the joyride,
  /// but must not overwrite what the device owner chose.
  Future<void> _persist(String key, Object? value) async {
    if (guestSession.isActive) return;
    await _box?.put(key, value);
  }

  Future<void> setLanguage(
    String code, {
    bool persistToAccount = true,
    bool rethrowAccountSaveFailure = false,
  }) async {
    if (!_isSupported(code)) return;
    final changed = _languageCode != code;
    _languageCode = code;
    await _persist('languageCode', code);
    if (persistToAccount) {
      final accountId = _accountIdProvider?.call();
      if (accountId != null && accountId.isNotEmpty) {
        await _cacheLanguage(accountId, code);
      }
    }
    if (changed) notifyListeners();
    if (persistToAccount) {
      try {
        await _accountSaver?.call(code);
      } catch (_) {
        // The local selection remains usable offline. The account write will
        // be retried the next time the user changes this setting.
        if (rethrowAccountSaveFailure) rethrow;
      }
    }
  }

  Future<void> markLanguageChosen(String userId, String code) async {
    if (!_isSupported(code)) return;
    _languageCode = code;
    await _accountSaver?.call(code);
    await _cacheLanguage(userId, code);
    final accountId = _accountIdProvider?.call();
    if (accountId != null && accountId.isNotEmpty && accountId != userId) {
      await _cacheLanguage(accountId, code);
    }
    await _persist('languageCode', code);
    notifyListeners();
  }

  Future<void> applyAccountLanguage(String userId, String code) async {
    if (!_isSupported(code)) return;
    final changed = _languageCode != code;
    _languageCode = code;
    await _cacheLanguage(userId, code);
    await _persist('languageCode', code);
    if (changed) notifyListeners();
  }

  Future<void> _cacheLanguage(String userId, String code) async {
    _languageByUser[userId] = code;
    _chosenLanguageUsers.add(userId);
    await _persist('languageByUser', Map<String, String>.from(_languageByUser));
    await _persist('chosenLanguageUsers', _chosenLanguageUsers.toList());
  }

  static bool _isSupported(String code) => code == 'en' || code == 'tr';
}

final localeService = LocaleService(
  accountSaver: accountPreferencesService.saveLanguage,
  accountIdProvider: () => accountPreferencesService.authenticatedUserId,
);
