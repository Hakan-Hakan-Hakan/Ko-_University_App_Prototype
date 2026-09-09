import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'guest_session.dart';

typedef AccountPreferencesRowLoader =
    Future<Map<String, dynamic>?> Function(String userId);
typedef AccountPreferencesRowWriter =
    Future<void> Function(String userId, Map<String, dynamic> values);

enum AccountPreferencesStatus { signedOut, loading, loaded, error }

enum AccountPreferencePrompt { none, language, theme }

@immutable
class AccountPreferences {
  final String? languageCode;
  final bool? isDark;

  const AccountPreferences({this.languageCode, this.isDark});

  factory AccountPreferences.fromRow(Map<String, dynamic>? row) {
    final language = row?['language_code'];
    final theme = row?['theme_mode'];
    return AccountPreferences(
      languageCode: language == 'en' || language == 'tr'
          ? language as String
          : null,
      isDark: theme == 'dark'
          ? true
          : theme == 'light'
          ? false
          : null,
    );
  }

  AccountPreferences copyWith({String? languageCode, bool? isDark}) {
    return AccountPreferences(
      languageCode: languageCode ?? this.languageCode,
      isDark: isDark ?? this.isDark,
    );
  }
}

/// Account-scoped language and appearance preferences.
///
/// Hive remains the fast local cache used to paint the first frame. This
/// service is the source of truth after authentication, so the same choices
/// follow a Supabase account to every device.
class AccountPreferencesService extends ChangeNotifier {
  AccountPreferencesService({
    SupabaseClient? Function()? clientProvider,
    String? Function()? userIdProvider,
    AccountPreferencesRowLoader? rowLoader,
    AccountPreferencesRowWriter? rowWriter,
    Duration requestTimeout = const Duration(seconds: 3),
  }) : _clientProvider = clientProvider,
       _userIdProvider = userIdProvider,
       _rowLoader = rowLoader,
       _rowWriter = rowWriter,
       _requestTimeout = requestTimeout;

  final SupabaseClient? Function()? _clientProvider;
  final String? Function()? _userIdProvider;
  final AccountPreferencesRowLoader? _rowLoader;
  final AccountPreferencesRowWriter? _rowWriter;
  final Duration _requestTimeout;

  AccountPreferences _preferences = const AccountPreferences();
  AccountPreferencesStatus _status = AccountPreferencesStatus.signedOut;
  String? _loadedUserId;
  Object? _lastError;
  int _requestGeneration = 0;
  final Map<String, AccountPreferences> _cacheByUser = {};

  AccountPreferences get preferences => _preferences;
  AccountPreferencesStatus get status => _status;
  Object? get lastError => _lastError;
  bool get hasLanguagePreference =>
      isLoadedForCurrentUser && _preferences.languageCode != null;
  bool get hasThemePreference =>
      isLoadedForCurrentUser && _preferences.isDark != null;
  String? get authenticatedUserId => _currentUserId;
  bool get hasAuthenticatedUser => _currentUserId != null;
  bool get isLoadedForCurrentUser {
    final userId = _currentUserId;
    return userId != null &&
        _loadedUserId == userId &&
        _status == AccountPreferencesStatus.loaded;
  }

  /// A missing value is actionable only after Supabase successfully returned
  /// the current account's row. A loading or failed request must never be
  /// treated as first-time setup.
  bool get needsLanguagePreference =>
      isLoadedForCurrentUser && _preferences.languageCode == null;
  bool get needsThemePreference =>
      isLoadedForCurrentUser && _preferences.isDark == null;
  AccountPreferencePrompt get nextRequiredPreference {
    if (!isLoadedForCurrentUser) return AccountPreferencePrompt.none;
    if (_preferences.languageCode == null) {
      return AccountPreferencePrompt.language;
    }
    if (_preferences.isDark == null) return AccountPreferencePrompt.theme;
    return AccountPreferencePrompt.none;
  }

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (_clientProvider != null) return _clientProvider();
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _currentUserId {
    final provided = _userIdProvider?.call();
    if (provided != null && provided.isNotEmpty) return provided;
    return _client?.auth.currentUser?.id;
  }

  Future<AccountPreferences> loadForCurrentUser() async {
    final userId = _currentUserId;
    final generation = ++_requestGeneration;
    if (userId == null) {
      clear();
      return const AccountPreferences();
    }

    _status = AccountPreferencesStatus.loading;
    _loadedUserId = userId;
    _preferences = _cacheByUser[userId] ?? const AccountPreferences();
    _lastError = null;
    notifyListeners();

    try {
      final row =
          await (_rowLoader != null
                  ? _rowLoader(userId)
                  : _loadSupabaseRow(userId))
              .timeout(_requestTimeout);

      // Do not let a late response from the previous account overwrite the
      // next account's state during a fast logout/login sequence.
      if (!_isCurrentRequest(userId, generation)) {
        return const AccountPreferences();
      }

      _preferences = AccountPreferences.fromRow(row);
      _cacheByUser[userId] = _preferences;
      _status = AccountPreferencesStatus.loaded;
      notifyListeners();
      return _preferences;
    } on TimeoutException catch (error) {
      if (_isCurrentRequest(userId, generation)) {
        // Keep an account-scoped value from an earlier successful fetch when
        // available. Otherwise neutral values avoid both a security bypass and
        // a false first-time preference prompt while offline.
        _preferences = _cacheByUser[userId] ?? const AccountPreferences();
        _lastError = error;
        _status = AccountPreferencesStatus.error;
        notifyListeners();
      }
      return _preferences;
    } catch (error) {
      if (_isCurrentRequest(userId, generation)) {
        _lastError = error;
        _status = AccountPreferencesStatus.error;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Explicit retry hook for login/router UI and connectivity recovery.
  Future<AccountPreferences> retry() => loadForCurrentUser();

  Future<void> saveLanguage(String code) async {
    if (code != 'en' && code != 'tr') return;
    final userId = _currentUserId;
    if (userId == null) return;
    await _save(userId, {'language_code': code});
    if (_currentUserId != userId) return;
    _preferences = _preferences.copyWith(languageCode: code);
    _cacheByUser[userId] = _preferences;
    _lastError = null;
    notifyListeners();
  }

  Future<void> saveTheme(bool isDark) async {
    final userId = _currentUserId;
    if (userId == null) return;
    await _save(userId, {'theme_mode': isDark ? 'dark' : 'light'});
    if (_currentUserId != userId) return;
    _preferences = _preferences.copyWith(isDark: isDark);
    _cacheByUser[userId] = _preferences;
    _lastError = null;
    notifyListeners();
  }

  void clear() {
    _requestGeneration++;
    final changed =
        _status != AccountPreferencesStatus.signedOut ||
        _loadedUserId != null ||
        _preferences.languageCode != null ||
        _preferences.isDark != null ||
        _lastError != null;
    _status = AccountPreferencesStatus.signedOut;
    _loadedUserId = null;
    _preferences = const AccountPreferences();
    _lastError = null;
    if (changed) notifyListeners();
  }

  bool _isCurrentRequest(String userId, int generation) {
    return generation == _requestGeneration && _currentUserId == userId;
  }

  Future<Map<String, dynamic>?> _loadSupabaseRow(String userId) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is required to load account preferences.');
    }
    final row = await client
        .from('user_preferences')
        .select('language_code, theme_mode')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> _save(String userId, Map<String, dynamic> values) async {
    if (_rowWriter != null) {
      await _rowWriter(userId, values).timeout(_requestTimeout);
    } else {
      final client = _client;
      if (client == null || client.auth.currentUser?.id != userId) {
        throw StateError(
          'An authenticated Supabase user is required to save preferences.',
        );
      }
      await client
          .from('user_preferences')
          .upsert({
            'user_id': userId,
            ...values,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id')
          .timeout(_requestTimeout);
    }
  }
}

final accountPreferencesService = AccountPreferencesService();
