import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'guest_session.dart';

/// Per-device state the CHATS handoff asks for but the data model has no field
/// for: a group's description and the starred/favourite flag on a thread.
///
/// **These are device-local, not shared.** `ChatGroup` carries only
/// `customName` and `photoUrl`, and there is no favourites table, so a
/// description typed here is visible to this device and nobody else. Giving
/// them real semantics means a new column plus a sync path, i.e. backend work,
/// which this redesign pass deliberately does not touch. Muting is the
/// exception and does not live here: `clubChatPrefs.isMuted` already stores it
/// per thread, so group threads reuse that.
///
/// The club room's "Save Message" is here for the same reason — there is no
/// saved-messages table, so a saved message is bookmarked on this device only.
class ChatGroupPrefs extends ChangeNotifier {
  static const _boxName = 'chat_group_prefs_v1';
  static const _descriptionsKey = 'descriptionsByThreadId';
  static const _favouritesKey = 'favouriteThreadIds';
  static const _savedMessagesKey = 'savedMessageIds';

  Box<dynamic>? _box;

  final Map<String, String> _descriptionsByThreadId = {};
  final Set<String> _favouriteThreadIds = {};
  final Set<String> _savedMessageIds = {};

  String descriptionFor(String threadId) =>
      _descriptionsByThreadId[threadId] ?? '';

  void setDescription(String threadId, String value) {
    final trimmed = value.trim();
    if (descriptionFor(threadId) == trimmed) return;
    if (trimmed.isEmpty) {
      _descriptionsByThreadId.remove(threadId);
    } else {
      _descriptionsByThreadId[threadId] = trimmed;
    }
    _persist(
      _descriptionsKey,
      Map<String, String>.from(_descriptionsByThreadId),
    );
  }

  bool isFavourite(String threadId) => _favouriteThreadIds.contains(threadId);

  void setFavourite(String threadId, bool favourite) {
    final changed = favourite
        ? _favouriteThreadIds.add(threadId)
        : _favouriteThreadIds.remove(threadId);
    if (!changed) return;
    _persist(_favouritesKey, _favouriteThreadIds.toList(growable: false));
  }

  bool isMessageSaved(String messageId) => _savedMessageIds.contains(messageId);

  void setMessageSaved(String messageId, bool saved) {
    final changed = saved
        ? _savedMessageIds.add(messageId)
        : _savedMessageIds.remove(messageId);
    if (!changed) return;
    _persist(_savedMessagesKey, _savedMessageIds.toList(growable: false));
  }

  Future<void> initialize() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final stored = _box?.get(_descriptionsKey);
    _descriptionsByThreadId.clear();
    if (stored is Map) {
      for (final entry in stored.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          _descriptionsByThreadId[entry.key.toString()] = value;
        }
      }
    }
    _favouriteThreadIds
      ..clear()
      ..addAll(
        (_box?.get(_favouritesKey) as List? ?? const []).map(
          (id) => id.toString(),
        ),
      );
    _savedMessageIds
      ..clear()
      ..addAll(
        (_box?.get(_savedMessagesKey) as List? ?? const []).map(
          (id) => id.toString(),
        ),
      );
    notifyListeners();
  }

  void _persist(String key, Object value) {
    if (guestSession.isActive) return;
    final box = _box;
    if (box != null) unawaited(box.put(key, value));
    notifyListeners();
  }
}

final chatGroupPrefs = ChatGroupPrefs();
