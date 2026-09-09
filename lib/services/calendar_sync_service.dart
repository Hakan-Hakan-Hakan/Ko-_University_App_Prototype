import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../models/event.dart';
import 'guest_session.dart';

class CalendarSyncService extends ChangeNotifier {
  static const _boxName = 'calendar_sync_v1';
  static const _iosCalendarChannel = MethodChannel('ku_app/apple_calendar');
  late Box<dynamic> _box;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    _initialized = true;
  }

  bool isSynced(String userId, String eventId) {
    if (!_initialized || userId.isEmpty) return false;
    return _box.get(_key(userId, eventId), defaultValue: false) == true;
  }

  /// Returns: 'authorized', 'notDetermined', 'denied', 'restricted', 'writeOnly'
  Future<String> checkPermission() async {
    if (!Platform.isIOS) return 'authorized';
    try {
      final status = await _iosCalendarChannel.invokeMethod<String>(
        'checkPermission',
      );
      return status ?? 'notDetermined';
    } on PlatformException {
      return 'notDetermined';
    }
  }

  /// Triggers the native iOS permission dialog. Returns true if granted.
  Future<bool> requestPermission() async {
    if (!Platform.isIOS) return true;
    try {
      final status = await _iosCalendarChannel.invokeMethod<String>(
        'requestPermission',
      );
      return status == 'authorized';
    } on PlatformException {
      return false;
    }
  }

  /// Sync a single event to the device calendar.
  Future<bool> addToDeviceCalendar(Event event, String userId) async {
    final count = await syncEventsToDeviceCalendar([event], userId);
    return count > 0;
  }

  Future<int> syncEventsToDeviceCalendar(
    List<Event> eventList,
    String userId,
  ) async {
    // Report the events as synced without touching the device calendar.
    if (guestSession.isActive) return eventList.length;
    if (!_initialized || userId.isEmpty || eventList.isEmpty) return 0;

    final unsynced = eventList
        .where(
          (event) =>
              _box.get(_key(userId, event.id), defaultValue: false) != true,
        )
        .toList();
    if (unsynced.isEmpty) return 0;

    if (Platform.isIOS) {
      return _syncEventsToAppleCalendar(unsynced, userId);
    }

    return 0;
  }

  Future<bool> removeEventFromDeviceCalendar(Event event, String userId) async {
    if (!_initialized || userId.isEmpty) return false;

    if (Platform.isIOS) {
      return _removeEventFromAppleCalendar(event, userId);
    }

    return false;
  }

  Future<void> markSynced(String userId, String eventId) async {
    if (guestSession.isActive) return;
    if (!_initialized || userId.isEmpty) return;
    await _box.put(_key(userId, eventId), true);
    notifyListeners();
  }

  Future<int> _syncEventsToAppleCalendar(
    List<Event> eventList,
    String userId,
  ) async {
    try {
      final syncedIds = await _iosCalendarChannel.invokeListMethod<String>(
        'syncEvents',
        {
          'events': eventList
              .map(
                (event) => {
                  'id': event.id,
                  'title': event.title,
                  'description': event.description,
                  'location': event.location,
                  'startDate': event.dateTime.millisecondsSinceEpoch,
                  'endDate': event.endTime.millisecondsSinceEpoch,
                },
              )
              .toList(),
        },
      );
      if (syncedIds == null || syncedIds.isEmpty) return 0;

      for (final id in syncedIds) {
        await _box.put(_key(userId, id), true);
      }
      notifyListeners();
      return syncedIds.length;
    } on PlatformException {
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> _removeEventFromAppleCalendar(Event event, String userId) async {
    if (guestSession.isActive) return false;
    try {
      final removed = await _iosCalendarChannel.invokeMethod<bool>(
        'removeEvent',
        {'id': event.id},
      );
      if (removed == true) {
        await _box.put(_key(userId, event.id), false);
        notifyListeners();
      }
      return removed == true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _key(String userId, String eventId) => '${userId}_$eventId';
}

final calendarSyncService = CalendarSyncService();
