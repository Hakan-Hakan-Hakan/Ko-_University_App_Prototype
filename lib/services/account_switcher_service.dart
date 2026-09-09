import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club.dart';
import 'auth_service.dart';
import 'lazy_content_loader.dart';
import 'mock_data.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

enum AccountKind { personal, club }

class SwitchableAccount {
  final AccountKind kind;
  final String id;
  final String name;
  final Club? club;

  SwitchableAccount.personal({required this.name, required this.id})
    : kind = AccountKind.personal,
      club = null;

  SwitchableAccount.club({required Club club})
    : kind = AccountKind.club,
      id = club.id,
      name = club.name,
      club = club;

  bool get isPersonal => kind == AccountKind.personal;
  bool get isClub => kind == AccountKind.club;
}

/// Keeps the real Supabase session on the student's account while selecting
/// which identity is allowed to author club content.
///
/// A club account is available only when the authenticated profile is still a
/// board member of that club. The selected club is also persisted remotely in
/// `club_account_contexts`; RLS uses that row and re-checks board membership
/// before allowing club content writes.
class AccountSwitcherService extends ChangeNotifier {
  static const _localSelectionPrefix = 'active_club_account_';

  String? _loadedUserId;
  String? _activeClubId;
  bool _isLoading = false;

  String? get _currentUserId => authService.currentUser?.id;

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

  Club? get activeClub {
    final userId = _currentUserId;
    if (userId == null || userId != _loadedUserId || _activeClubId == null) {
      return null;
    }
    for (final club in clubs) {
      if (club.id == _activeClubId && club.boardMemberIds.contains(userId)) {
        return club;
      }
    }
    return null;
  }

  bool get isClubAccountActive => activeClub != null;

  /// The real auth identity that should be written to actor/audit columns.
  String get actorId =>
      _client?.auth.currentUser?.id ??
      authService.currentUser?.id ??
      authService.currentAdmin?.id ??
      '';

  List<Club> get availableClubs {
    final userId = _currentUserId;
    if (userId == null || userId != _loadedUserId) return const [];
    return clubs
        .where((club) => club.boardMemberIds.contains(userId))
        .toList(growable: false);
  }

  List<SwitchableAccount> get accounts {
    final user = authService.currentUser;
    if (user == null || _loadedUserId != user.id) return const [];
    return [
      SwitchableAccount.personal(id: user.id, name: user.name),
      ...availableClubs.map((club) => SwitchableAccount.club(club: club)),
    ];
  }

  SwitchableAccount? get activeAccount {
    final user = authService.currentUser;
    if (user == null) return null;
    final club = activeClub;
    return club == null
        ? SwitchableAccount.personal(id: user.id, name: user.name)
        : SwitchableAccount.club(club: club);
  }

  bool get hasSwitchableAccounts => availableClubs.isNotEmpty;

  /// Loads the public club snapshot before evaluating board membership, then
  /// restores the selected context for this personal account.
  Future<void> prepare() async {
    final userId = _currentUserId;
    if (userId == null) {
      clear();
      return;
    }
    if (_isLoading) return;

    // The guest joyride has no remote context row and must not leave a
    // selection behind in preferences, so its POV lives purely in memory.
    // Board membership is still re-checked on every `activeClub` read.
    if (guestSession.isActive) {
      final changed = _loadedUserId != userId;
      _loadedUserId = userId;
      if (changed) notifyListeners();
      return;
    }

    _isLoading = true;
    try {
      try {
        await lazyContentLoader.ensureContentLoaded();
      } catch (_) {
        // Cached/local clubs are still useful for mock mode and offline UI.
      }
      await _loadSelection(userId);
    } finally {
      _isLoading = false;
    }
  }

  Future<bool> select(SwitchableAccount account) async {
    final userId = _currentUserId;
    if (userId == null) return false;
    if (_loadedUserId != userId) await prepare();

    final clubId = account.isClub ? account.club?.id : null;
    if (clubId != null && !availableClubs.any((club) => club.id == clubId)) {
      return false;
    }

    if (guestSession.isActive) {
      _loadedUserId = userId;
      _activeClubId = clubId;
      notifyListeners();
      return true;
    }

    final client = _client;
    try {
      if (client != null) {
        if (clubId == null) {
          await client
              .from('club_account_contexts')
              .delete()
              .eq('user_id', userId);
        } else {
          await client.from('club_account_contexts').upsert({
            'user_id': userId,
            'club_id': clubId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id');
        }
      }
    } catch (_) {
      return false;
    }

    _loadedUserId = userId;
    _activeClubId = clubId;
    final preferences = await SharedPreferences.getInstance();
    final key = '$_localSelectionPrefix$userId';
    if (clubId == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, clubId);
    }
    notifyListeners();
    return true;
  }

  void clear() {
    if (_loadedUserId == null && _activeClubId == null) return;
    _loadedUserId = null;
    _activeClubId = null;
    notifyListeners();
  }

  Future<void> _loadSelection(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '$_localSelectionPrefix$userId';
    String? clubId = preferences.getString(key);

    final client = _client;
    if (client != null) {
      try {
        final row = await client
            .from('club_account_contexts')
            .select('club_id')
            .eq('user_id', userId)
            .maybeSingle();
        clubId = row?['club_id']?.toString();
      } catch (_) {
        // A local selection can still paint while an older backend is being
        // migrated. The first selection attempt will surface a write error.
      }
    }

    final isValid =
        clubId != null && availableClubs.any((club) => club.id == clubId);
    if (!isValid) {
      clubId = null;
      await preferences.remove(key);
    }

    final changed = _loadedUserId != userId || _activeClubId != clubId;
    _loadedUserId = userId;
    _activeClubId = clubId;
    if (changed) notifyListeners();
  }
}

final accountSwitcherService = AccountSwitcherService();
