import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/news_post.dart';
import 'supabase_interaction_service.dart';
import 'guest_session.dart';

/// Central poll-vote state store, keyed by post id.
///
/// Mirrors RSVP/like behavior: optimistic local vote first (Hive-persisted),
/// Supabase upsert in the background, rollback on failure. Votes on seed posts
/// (non-UUID ids) stay local.
class PollStore extends ChangeNotifier {
  static const _boxName = 'poll_votes_v1';

  /// postId → (voterId → optionIndex). Remote voters merge in on hydrate.
  final Map<String, Map<String, int>> _votes = {};

  /// Aggregate-only option totals supplied by Feed v2. No voter identities are
  /// retained for these posts; the current viewer remains in [_votes].
  final Map<String, List<int>> _feedOptionCounts = {};
  final Set<String> _hydratedPostIds = {};
  Box<dynamic>? _box;

  static final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _looksLikeUuid(String value) => _uuidRe.hasMatch(value);

  Future<void> initialize() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get('votes');
    if (raw is Map) {
      _votes.clear();
      raw.forEach((postId, voters) {
        _votes[postId.toString()] = {
          for (final e in (voters as Map).entries)
            e.key.toString(): e.value as int,
        };
      });
      notifyListeners();
    }
  }

  void _save() {
    if (guestSession.isActive) return;
    final box = _box;
    if (box == null) return;
    unawaited(
      box.put('votes', {
        for (final e in _votes.entries) e.key: Map<String, int>.from(e.value),
      }),
    );
  }

  int? myVote(String postId, String userId) => _votes[postId]?[userId];

  int totalVotes(String postId) =>
      _feedOptionCounts[postId]?.fold<int>(0, (sum, value) => sum + value) ??
      _votes[postId]?.length ??
      0;

  int votesForOption(String postId, int optionIndex) =>
      optionIndex >= 0 && optionIndex < (_feedOptionCounts[postId]?.length ?? 0)
      ? _feedOptionCounts[postId]![optionIndex]
      : _votes[postId]?.values.where((v) => v == optionIndex).length ?? 0;

  /// Seeds aggregate poll results and only the authenticated viewer's vote.
  /// This replaces the legacy feed's download of every voter identity.
  void seedFeedSummaries({
    required Map<String, List<int>> optionCountsByPostId,
    required Map<String, int?> viewerVotesByPostId,
    required String userId,
  }) {
    if (optionCountsByPostId.isEmpty) return;
    for (final entry in optionCountsByPostId.entries) {
      _feedOptionCounts[entry.key] = List<int>.from(entry.value);
      _hydratedPostIds.add(entry.key);
      if (userId.isEmpty) continue;
      final voters = _votes.putIfAbsent(entry.key, () => {});
      final viewerVote = viewerVotesByPostId[entry.key];
      if (viewerVote == null) {
        voters.remove(userId);
      } else {
        voters[userId] = viewerVote;
      }
    }
    _save();
    notifyListeners();
  }

  /// Seeds remote votes for many posts at once (from the batched poll_votes
  /// query at content load) and marks them hydrated, so [hydrate] becomes a
  /// no-op for feed polls.
  void seedRemoteVotes(Map<String, Map<String, int>> votesByPostId) {
    if (votesByPostId.isEmpty) return;
    var changed = false;
    for (final entry in votesByPostId.entries) {
      _hydratedPostIds.add(entry.key);
      if (entry.value.isEmpty) continue;
      final local = _votes.putIfAbsent(entry.key, () => {});
      local.addAll(entry.value);
      changed = true;
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  /// Merges remote votes for [postId] (once per session; [force] refreshes).
  /// [pollId], when known, skips the poll-id lookup query.
  Future<void> hydrate(
    String postId, {
    String? pollId,
    bool force = false,
  }) async {
    if (!force && _hydratedPostIds.contains(postId)) return;
    _hydratedPostIds.add(postId);
    if (!_looksLikeUuid(postId)) return;

    try {
      final remote = await supabaseInteractionService.fetchPollVotes(
        postId,
        pollId: pollId,
        force: force,
      );
      if (remote.isEmpty) return;
      final local = _votes.putIfAbsent(postId, () => {});
      local.addAll(remote);
      _save();
      notifyListeners();
    } catch (error) {
      debugPrint('Poll hydrate failed for $postId: $error');
      _hydratedPostIds.remove(postId);
    }
  }

  /// Optimistically records (or changes) [userId]'s vote.
  Future<void> vote({
    required NewsPost post,
    required String userId,
    required int optionIndex,
  }) async {
    final options = post.poll?.options ?? const [];
    if (userId.isEmpty || optionIndex < 0 || optionIndex >= options.length) {
      return;
    }

    final voters = _votes.putIfAbsent(post.id, () => {});
    final previous = voters[userId];
    if (previous == optionIndex) return;
    final feedCounts = _feedOptionCounts[post.id];
    if (feedCounts != null) {
      if (previous != null && previous >= 0 && previous < feedCounts.length) {
        feedCounts[previous] = (feedCounts[previous] - 1).clamp(0, 1 << 31);
      }
      feedCounts[optionIndex] = feedCounts[optionIndex] + 1;
    }
    voters[userId] = optionIndex;
    _save();
    notifyListeners();

    if (!_looksLikeUuid(post.id) || !_looksLikeUuid(userId)) return;
    try {
      await supabaseInteractionService.upsertPollVote(
        postId: post.id,
        optionIndex: optionIndex,
        pollId: post.poll?.pollId,
      );
    } catch (error) {
      debugPrint('Poll vote supabase write failed: $error');
      if (feedCounts != null) {
        feedCounts[optionIndex] = (feedCounts[optionIndex] - 1).clamp(
          0,
          1 << 31,
        );
        if (previous != null && previous >= 0 && previous < feedCounts.length) {
          feedCounts[previous] = feedCounts[previous] + 1;
        }
      }
      if (previous == null) {
        voters.remove(userId);
      } else {
        voters[userId] = previous;
      }
      _save();
      notifyListeners();
    }
  }

  /// Drops in-memory votes at a session boundary.
  ///
  /// Guest votes never reach Hive (see [_save]), but these maps outlive the
  /// session, so without this a guest's votes would still be showing after
  /// they log out and a real account signs in on the same process.
  void clearSessionState() {
    _votes.clear();
    _feedOptionCounts.clear();
    _hydratedPostIds.clear();
    notifyListeners();
  }
}

final pollStore = PollStore();
