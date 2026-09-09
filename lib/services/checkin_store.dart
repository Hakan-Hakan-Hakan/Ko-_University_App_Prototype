import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'supabase_interaction_service.dart';
import 'guest_session.dart';

/// Central event check-in state store (QR Event Pass scans + manual toggles).
///
/// Mirrors RSVP behavior: optimistic local update first (persisted to Hive so
/// door check-ins survive restarts offline), Supabase write in the background,
/// rollback on failure. Check-ins for seed events (non-UUID ids) stay local.
class CheckinStore extends ChangeNotifier {
  static const _boxName = 'event_checkins_v1';

  final Map<String, Set<String>> _byEvent = {};
  final Set<String> _hydratedEventIds = {};
  Box<dynamic>? _box;

  static final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _looksLikeUuid(String value) => _uuidRe.hasMatch(value);

  Future<void> initialize() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get('checkins');
    if (raw is Map) {
      _byEvent.clear();
      raw.forEach((eventId, ids) {
        _byEvent[eventId.toString()] = {
          for (final id in ids as List) id.toString(),
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
      box.put('checkins', {
        for (final e in _byEvent.entries) e.key: e.value.toList(),
      }),
    );
  }

  bool isCheckedIn(String eventId, String userId) =>
      _byEvent[eventId]?.contains(userId) ?? false;

  int countFor(String eventId) => _byEvent[eventId]?.length ?? 0;

  Set<String> checkedInIds(String eventId) =>
      Set.unmodifiable(_byEvent[eventId] ?? const {});

  /// Merges remote check-ins for [eventId] (once per session; [force] refreshes).
  Future<void> hydrate(String eventId, {bool force = false}) async {
    if (!force && _hydratedEventIds.contains(eventId)) return;
    _hydratedEventIds.add(eventId);
    if (!_looksLikeUuid(eventId)) return;

    try {
      final remote = await supabaseInteractionService.fetchEventCheckinIds(
        eventId,
        force: force,
      );
      if (remote.isEmpty) return;
      final local = _byEvent.putIfAbsent(eventId, () => {});
      final sizeBefore = local.length;
      local.addAll(remote);
      if (local.length != sizeBefore) {
        _save();
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Check-in hydrate failed for $eventId: $error');
      _hydratedEventIds.remove(eventId);
    }
  }

  /// Optimistically toggles a check-in; Supabase write in the background with
  /// rollback on failure. Returns the new checked-in state.
  Future<bool> toggle({
    required String eventId,
    required String userId,
    String method = 'manual',
  }) async {
    final wasCheckedIn = isCheckedIn(eventId, userId);
    _setLocal(eventId, userId, !wasCheckedIn);

    if (_looksLikeUuid(eventId) && _looksLikeUuid(userId)) {
      try {
        await supabaseInteractionService.setEventCheckin(
          eventId: eventId,
          profileId: userId,
          checkedIn: !wasCheckedIn,
          method: method,
        );
      } catch (error) {
        debugPrint('Check-in supabase write failed: $error');
        _setLocal(eventId, userId, wasCheckedIn);
        return wasCheckedIn;
      }
    }
    return !wasCheckedIn;
  }

  void _setLocal(String eventId, String userId, bool checkedIn) {
    final set = _byEvent.putIfAbsent(eventId, () => {});
    if (checkedIn) {
      set.add(userId);
    } else {
      set.remove(userId);
    }
    _save();
    notifyListeners();
  }

  /// Drops in-memory check-ins at a session boundary. See
  /// `PollStore.clearSessionState` for why this is needed.
  void clearSessionState() {
    _byEvent.clear();
    _hydratedEventIds.clear();
    notifyListeners();
  }
}

final checkinStore = CheckinStore();
