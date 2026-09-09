import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comment.dart';
import '../models/news_post.dart';
import 'admin_moderation_service.dart';
import 'auth_service.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

/// Local safety state plus the authenticated Supabase moderation queue.
///
/// Reports and blocks take effect locally before network work begins. This is
/// intentional: objectionable content disappears immediately even if the
/// device is offline, while the server write is retried by the user if it
/// cannot be delivered.
class ModerationService extends ChangeNotifier {
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final Set<String> _hiddenPostIds = {};
  final Set<String> _hiddenCommentIds = {};
  final Set<String> _blockedUserIds = {};
  final Set<String> _blockedClubIds = {};
  String? _activeUserId;

  Set<String> get hiddenPostIds => Set.unmodifiable(_hiddenPostIds);
  Set<String> get hiddenCommentIds => Set.unmodifiable(_hiddenCommentIds);
  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);
  Set<String> get blockedClubIds => Set.unmodifiable(_blockedClubIds);

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

  String get _actorId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  String _hiddenKey(String userId) => 'moderation_hidden_posts_$userId';
  String _hiddenCommentsKey(String userId) =>
      'moderation_hidden_comments_$userId';
  String _blockedKey(String userId) => 'moderation_blocked_users_$userId';
  String _blockedClubsKey(String userId) => 'moderation_blocked_clubs_$userId';

  bool isPostHidden(NewsPost post) =>
      _hiddenPostIds.contains(post.id) ||
      _blockedClubIds.contains(post.clubId) ||
      (post.authorId.isNotEmpty && _blockedUserIds.contains(post.authorId));

  bool isCommentHidden(Comment comment) =>
      _hiddenCommentIds.contains(comment.id) ||
      (comment.userId.isNotEmpty && _blockedUserIds.contains(comment.userId));

  bool isUserBlocked(String userId) => _blockedUserIds.contains(userId);
  bool isClubBlocked(String clubId) => _blockedClubIds.contains(clubId);

  /// Loads this account's safety choices and merges server-side blocks.
  Future<void> activateForUser(String userId) async {
    if (userId.isEmpty) return;
    _activeUserId = userId;
    final preferences = await SharedPreferences.getInstance();
    _hiddenPostIds
      ..clear()
      ..addAll(preferences.getStringList(_hiddenKey(userId)) ?? const []);
    _hiddenCommentIds
      ..clear()
      ..addAll(
        preferences.getStringList(_hiddenCommentsKey(userId)) ?? const [],
      );
    _blockedUserIds
      ..clear()
      ..addAll(preferences.getStringList(_blockedKey(userId)) ?? const []);
    _blockedClubIds
      ..clear()
      ..addAll(preferences.getStringList(_blockedClubsKey(userId)) ?? const []);
    notifyListeners();

    final client = _client;
    if (client == null || !_uuidPattern.hasMatch(userId)) return;
    try {
      final results = await Future.wait([
        client
            .from('user_blocks')
            .select('blocked_id')
            .eq('blocker_id', userId),
        client.from('club_blocks').select('club_id').eq('blocker_id', userId),
      ]);
      final rows = results[0];
      _blockedUserIds.addAll(
        rows
            .map((row) => (row as Map)['blocked_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
      _blockedClubIds.addAll(
        results[1]
            .map((row) => (row as Map)['club_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
      await _persist();
      notifyListeners();
    } catch (error) {
      debugPrint('Could not hydrate moderation blocks: $error');
    }
  }

  void clearActiveUser() {
    _activeUserId = null;
    _hiddenPostIds.clear();
    _hiddenCommentIds.clear();
    _blockedUserIds.clear();
    _blockedClubIds.clear();
    notifyListeners();
  }

  /// Queues a post report and removes the post from this user's feed now.
  Future<void> reportPost(NewsPost post, {required String reason}) async {
    _hiddenPostIds.add(post.id);
    await _persist();
    notifyListeners();
    await _submitReport(
      targetType: 'post',
      targetId: post.id,
      reportedUserId: post.authorId,
      reportedClubId: post.clubId,
      reason: reason,
      snapshot: post.content,
    );
  }

  /// Queues a comment report and removes the comment from this user's view
  /// now, matching the immediate-removal guarantee made for reported posts.
  Future<void> reportComment(Comment comment, {required String reason}) async {
    _hiddenCommentIds.add(comment.id);
    await _persist();
    notifyListeners();
    await _submitReport(
      targetType: 'comment',
      targetId: comment.id,
      reportedUserId: comment.userId,
      reason: reason,
      snapshot: comment.content,
    );
  }

  Future<void> reportUser(String userId, {required String reason}) {
    return _submitReport(
      targetType: 'profile',
      targetId: userId,
      reportedUserId: userId,
      reason: reason,
    );
  }

  /// Blocks an abusive account and creates a moderation report in the same
  /// action so the developer is notified of every block.
  Future<void> blockUser(String userId, {required String reason}) async {
    final actorId = _actorId;
    if (userId.isEmpty || userId == actorId) return;

    _blockedUserIds.add(userId);
    await _persist();
    notifyListeners();

    final client = _client;
    if (client != null &&
        _uuidPattern.hasMatch(actorId) &&
        _uuidPattern.hasMatch(userId)) {
      try {
        await client.from('user_blocks').upsert({
          'blocker_id': actorId,
          'blocked_id': userId,
        }, onConflict: 'blocker_id,blocked_id');
      } catch (error) {
        debugPrint('Could not sync user block: $error');
      }
    }

    await _submitReport(
      targetType: 'profile',
      targetId: userId,
      reportedUserId: userId,
      reason: reason,
      source: 'block',
    );
  }

  Future<void> unblockUser(String userId) async {
    if (!_blockedUserIds.contains(userId)) return;
    final actorId = _actorId;
    _blockedUserIds.remove(userId);
    await _persist();
    notifyListeners();

    final client = _client;
    if (client == null ||
        !_uuidPattern.hasMatch(actorId) ||
        !_uuidPattern.hasMatch(userId)) {
      return;
    }
    try {
      await client
          .from('user_blocks')
          .delete()
          .eq('blocker_id', actorId)
          .eq('blocked_id', userId);
    } catch (error) {
      _blockedUserIds.add(userId);
      await _persist();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> blockClub(String clubId, {required String reason}) async {
    final actorId = _actorId;
    if (clubId.isEmpty) return;

    _blockedClubIds.add(clubId);
    await _persist();
    notifyListeners();

    final client = _client;
    if (client != null &&
        _uuidPattern.hasMatch(actorId) &&
        _uuidPattern.hasMatch(clubId)) {
      try {
        await client.from('club_blocks').upsert({
          'blocker_id': actorId,
          'club_id': clubId,
        }, onConflict: 'blocker_id,club_id');
      } catch (error) {
        debugPrint('Could not sync club block: $error');
      }
    }

    await _submitReport(
      targetType: 'club',
      targetId: clubId,
      reportedClubId: clubId,
      reason: reason,
      source: 'block',
    );
  }

  Future<void> unblockClub(String clubId) async {
    if (!_blockedClubIds.contains(clubId)) return;
    final actorId = _actorId;
    _blockedClubIds.remove(clubId);
    await _persist();
    notifyListeners();

    final client = _client;
    if (client == null ||
        !_uuidPattern.hasMatch(actorId) ||
        !_uuidPattern.hasMatch(clubId)) {
      return;
    }
    try {
      await client
          .from('club_blocks')
          .delete()
          .eq('blocker_id', actorId)
          .eq('club_id', clubId);
    } catch (error) {
      _blockedClubIds.add(clubId);
      await _persist();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _submitReport({
    required String targetType,
    required String targetId,
    required String reason,
    String? reportedUserId,
    String? reportedClubId,
    String? snapshot,
    String source = 'report',
  }) async {
    final actorId = _actorId;
    await adminModerationService.recordReport(
      reporterId: actorId,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      source: source,
      reportedUserId: reportedUserId,
      reportedClubId: reportedClubId,
      contentSnapshot: snapshot,
    );

    final client = _client;
    if (client == null || !_uuidPattern.hasMatch(actorId)) return;

    final payload = <String, dynamic>{
      'reporter_id': actorId,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'source': source,
    };
    if (reportedUserId != null && _uuidPattern.hasMatch(reportedUserId)) {
      payload['reported_user_id'] = reportedUserId;
    }
    final trimmedSnapshot = snapshot?.trim() ?? '';
    if (trimmedSnapshot.isNotEmpty) {
      payload['content_snapshot'] = trimmedSnapshot.length > 2000
          ? trimmedSnapshot.substring(0, 2000)
          : trimmedSnapshot;
    }

    try {
      await client.from('moderation_reports').insert(payload);
    } catch (error) {
      debugPrint('Could not submit moderation report: $error');
      rethrow;
    }
  }

  Future<void> _persist() async {
    if (guestSession.isActive) return;
    final userId = _activeUserId ?? _actorId;
    if (userId.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(_hiddenKey(userId), _hiddenPostIds.toList()),
      preferences.setStringList(
        _hiddenCommentsKey(userId),
        _hiddenCommentIds.toList(),
      ),
      preferences.setStringList(_blockedKey(userId), _blockedUserIds.toList()),
      preferences.setStringList(
        _blockedClubsKey(userId),
        _blockedClubIds.toList(),
      ),
    ]);
  }
}

final moderationService = ModerationService();
