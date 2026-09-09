import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chat_store.dart';
import '../services/mock_data.dart';
import '../services/rsvp_store.dart';
import '../services/user_state.dart';
import '../services/guest_session.dart';

/// The post-tour starter checklist: follow a club, RSVP to an event, say hi.
///
/// Started when a student finishes (or skips) onboarding. Items check
/// themselves off by observing the real stores. Detection is baseline-relative
/// so existing follows and RSVPs do not count as new onboarding actions.
///
/// State is persisted per user as JSON under `onboarding_checklist_<userId>`,
/// and done-flags are sticky: un-following later doesn't un-check the item.
class StarterChecklistService extends ChangeNotifier {
  static const String _prefix = 'onboarding_checklist_';

  SharedPreferences? _preferences;
  bool _listening = false;

  String _userId = '';
  bool _started = false;
  bool _dismissed = false;
  bool _followDone = false;
  bool _rsvpDone = false;
  bool _chatDone = false;
  int _baselineFollowCount = 0;
  int _baselineRsvpCount = 0;
  DateTime? _startedAt;

  bool get followDone => _followDone;
  bool get rsvpDone => _rsvpDone;
  bool get chatDone => _chatDone;
  bool get allDone => _followDone && _rsvpDone && _chatDone;

  /// Whether the profile card should be visible for [userId].
  bool isActiveFor(String userId) =>
      _started &&
      userId.isNotEmpty &&
      userId == _userId &&
      !_dismissed &&
      !allDone;

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  /// Begins (or resumes) the checklist for [userId], snapshotting baselines
  /// on first start. Safe to call again on replays — existing progress wins.
  Future<void> startFor(String userId) async {
    if (userId.isEmpty || _preferences == null) return;
    _userId = userId;
    final raw = _preferences!.getString('$_prefix$userId');
    if (raw != null) {
      _loadFrom(raw);
    } else {
      _started = true;
      _dismissed = false;
      _followDone = false;
      _rsvpDone = false;
      _chatDone = false;
      _baselineFollowCount = userState.followedClubIds.length;
      _baselineRsvpCount = _attendingCount();
      _startedAt = DateTime.now();
      await _persist();
    }
    _attachListeners();
    _recheck();
    notifyListeners();
  }

  Future<void> dismiss() async {
    if (!_started || _dismissed) return;
    _dismissed = true;
    await _persist();
    notifyListeners();
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  void _attachListeners() {
    if (_listening) return;
    _listening = true;
    userState.addListener(_recheck);
    rsvpStore.addListener(_recheck);
    chatStore.addListener(_recheck);
  }

  int _attendingCount() =>
      events.where((event) => rsvpStore.isAttending(event.id)).length;

  bool _sentMessageSinceStart() {
    final startedAt = _startedAt;
    if (startedAt == null) return false;
    for (final thread in chatStore.threadsFor(_userId)) {
      final messages = chatStore.messagesFor(
        thread.threadId,
        viewerId: _userId,
      );
      for (final message in messages) {
        if (message.senderId == _userId &&
            message.createdAt.isAfter(startedAt)) {
          return true;
        }
      }
    }
    return false;
  }

  void _recheck() {
    if (!_started || _userId.isEmpty || allDone) return;
    var changed = false;
    if (!_followDone &&
        userState.followedClubIds.length > _baselineFollowCount) {
      _followDone = true;
      changed = true;
    }
    if (!_rsvpDone && _attendingCount() > _baselineRsvpCount) {
      _rsvpDone = true;
      changed = true;
    }
    if (!_chatDone && _sentMessageSinceStart()) {
      _chatDone = true;
      changed = true;
    }
    if (changed) {
      unawaited(_persist());
      notifyListeners();
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    if (guestSession.isActive) return;
    if (_preferences == null || _userId.isEmpty) return;
    await _preferences!.setString(
      '$_prefix$_userId',
      jsonEncode(<String, Object?>{
        'started': _started,
        'dismissed': _dismissed,
        'followDone': _followDone,
        'rsvpDone': _rsvpDone,
        'chatDone': _chatDone,
        'baselineFollowCount': _baselineFollowCount,
        'baselineRsvpCount': _baselineRsvpCount,
        'startedAtMillis': _startedAt?.millisecondsSinceEpoch,
      }),
    );
  }

  void _loadFrom(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _started = data['started'] as bool? ?? false;
      _dismissed = data['dismissed'] as bool? ?? false;
      _followDone = data['followDone'] as bool? ?? false;
      _rsvpDone = data['rsvpDone'] as bool? ?? false;
      _chatDone = data['chatDone'] as bool? ?? false;
      _baselineFollowCount = data['baselineFollowCount'] as int? ?? 0;
      _baselineRsvpCount = data['baselineRsvpCount'] as int? ?? 0;
      final millis = data['startedAtMillis'] as int?;
      _startedAt = millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      _started = false;
    }
  }
}

final starterChecklistService = StarterChecklistService();
