import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'guest_session.dart';

/// How message groups are laid out in a club community stream.
enum ClubMessageStyle { rows, bubbles, cards }

/// How much visual weight an officer announcement carries.
enum ClubAnnouncementEmphasis { subtle, tinted, bold }

/// Built-in community wallpapers. Stored by thread so every club can keep a
/// distinct background without requiring image-file permissions.
enum ClubChatBackground { classic, warm, ocean, forest, midnight }

/// Per-device preferences for the club community screen.
class ClubChatPrefs extends ChangeNotifier {
  static const _boxName = 'club_chat_prefs_v1';

  Box<dynamic>? _box;

  final Set<String> _mutedThreadIds = {};
  final Map<String, ClubChatBackground> _backgroundsByThreadId = {};

  /// Pinned strips the reader dismissed, by message id. Kept per device so a
  /// dismissed strip stays dismissed but a newly pinned notice comes back.
  final Set<String> _dismissedPinIds = {};

  /// Community presentation is intentionally consistent for every user.
  ClubMessageStyle get messageStyle => ClubMessageStyle.bubbles;
  ClubAnnouncementEmphasis get announcementEmphasis =>
      ClubAnnouncementEmphasis.tinted;
  bool get showRoles => true;

  ClubChatBackground backgroundFor(String threadId) =>
      _backgroundsByThreadId[threadId] ?? ClubChatBackground.classic;

  bool isMuted(String threadId) => _mutedThreadIds.contains(threadId);

  void setMuted(String threadId, bool muted) {
    final changed = muted
        ? _mutedThreadIds.add(threadId)
        : _mutedThreadIds.remove(threadId);
    if (!changed) return;
    _persist('mutedThreadIds', _mutedThreadIds.toList(growable: false));
  }

  bool isPinDismissed(String messageId) => _dismissedPinIds.contains(messageId);

  void dismissPin(String messageId) {
    if (!_dismissedPinIds.add(messageId)) return;
    _persist('dismissedPinIds', _dismissedPinIds.toList(growable: false));
  }

  Future<void> initialize() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    _mutedThreadIds
      ..clear()
      ..addAll(_readIds('mutedThreadIds'));
    _dismissedPinIds
      ..clear()
      ..addAll(_readIds('dismissedPinIds'));
    final storedBackgrounds = _box!.get('backgroundsByThreadId');
    if (storedBackgrounds is Map) {
      _backgroundsByThreadId
        ..clear()
        ..addEntries(
          storedBackgrounds.entries.map((entry) {
            final stored = entry.value?.toString();
            final background = ClubChatBackground.values.firstWhere(
              (value) => value.name == stored,
              orElse: () => ClubChatBackground.classic,
            );
            return MapEntry(entry.key.toString(), background);
          }),
        );
    }
    notifyListeners();
  }

  Iterable<String> _readIds(String key) =>
      (_box?.get(key) as List? ?? const []).map((id) => id.toString());

  void setBackground(String threadId, ClubChatBackground value) {
    if (threadId.isEmpty || backgroundFor(threadId) == value) return;
    if (value == ClubChatBackground.classic) {
      _backgroundsByThreadId.remove(threadId);
    } else {
      _backgroundsByThreadId[threadId] = value;
    }
    _persist('backgroundsByThreadId', {
      for (final entry in _backgroundsByThreadId.entries)
        entry.key: entry.value.name,
    });
  }

  void _persist(String key, Object value) {
    if (guestSession.isActive) return;
    final box = _box;
    if (box != null) unawaited(box.put(key, value));
    notifyListeners();
  }
}

final clubChatPrefs = ClubChatPrefs();
