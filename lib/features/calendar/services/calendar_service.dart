import 'dart:io';
import 'package:collection/collection.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../../l10n/app_localizations.dart';
import '../../../services/locale_service.dart';
import '../data/calendar_event_model.dart';
import '../providers/calendar_state.dart';
import '../../../services/guest_session.dart';

class CalendarResult {
  final bool success;
  final String? error;
  final bool isDuplicate;

  const CalendarResult({
    required this.success,
    this.error,
    this.isDuplicate = false,
  });
}

class CalendarService {
  // No BuildContext is available this deep in the service layer; these
  // fallbacks are resolved here via the current locale rather than pushed
  // up to a caller that may not exist yet.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(Locale(localeService.languageCode));

  static const _prefPrefix = 'myclubs_cal_';
  static const _initialPermissionPromptSeenKey =
      'myclubs_calendar_permission_prompt_seen_v1';
  static const _iosCalendarChannel = MethodChannel('ku_app/apple_calendar');
  final dc.DeviceCalendarPlugin _plugin = dc.DeviceCalendarPlugin();
  bool _tzInitialized = false;

  void _initTz() {
    if (_tzInitialized) return;
    tz_data.initializeTimeZones();
    _tzInitialized = true;
  }

  Future<CalendarPermissionState> checkPermission() async {
    try {
      if (Platform.isIOS) {
        final status = await _iosCalendarChannel.invokeMethod<String>(
          'checkPermission',
        );
        return _fromIosStatus(status);
      }
      final status = await ph.Permission.calendarWriteOnly.status;
      return _fromStatus(status);
    } catch (_) {
      return CalendarPermissionState.unknown;
    }
  }

  Future<CalendarPermissionState> requestPermission() async {
    try {
      if (Platform.isIOS) {
        final status = await _iosCalendarChannel.invokeMethod<String>(
          'requestPermission',
        );
        return _fromIosStatus(status);
      }
      final result = await _plugin.requestPermissions();
      if (result.isSuccess && result.data == true) {
        return CalendarPermissionState.granted;
      }
      return await checkPermission();
    } catch (_) {
      return CalendarPermissionState.denied;
    }
  }

  Future<void> openSettings() => ph.openAppSettings();

  Future<bool> hasShownInitialPermissionPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_initialPermissionPromptSeenKey) ?? false;
  }

  Future<void> markInitialPermissionPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_initialPermissionPromptSeenKey, true);
  }

  Future<CalendarResult> addEvent(CalendarEventModel model) async {
    // The guest joyride shows this working but must leave nothing behind on
    // the visitor's device, so no permission is requested and no event is
    // written — the caller still gets the success it would have got.
    if (guestSession.isActive) return const CalendarResult(success: true);
    try {
      if (Platform.isIOS) {
        return await _addEventToAppleCalendar(model);
      }

      _initTz();
      final calId = await _findWritableCalendarId();
      if (calId == null) {
        return CalendarResult(
          success: false,
          error: _l10n.calendarNoWritableCalendar,
        );
      }

      if (await _isDuplicate(calId, model)) {
        return const CalendarResult(success: true, isDuplicate: true);
      }

      final local = tz.local;
      final dcEvent = dc.Event(
        calId,
        title: model.title,
        description: model.description.isNotEmpty ? model.description : null,
        location: model.location.isNotEmpty ? model.location : null,
        start: tz.TZDateTime.from(model.startDate, local),
        end: tz.TZDateTime.from(model.endDate, local),
        reminders: [dc.Reminder(minutes: 30)],
        url: model.url != null ? Uri.tryParse(model.url!) : null,
      );

      final result = await _plugin.createOrUpdateEvent(dcEvent);
      if (result == null || !result.isSuccess) {
        final msg =
            result?.errors
                .map((e) => e.errorMessage)
                .where((s) => s.isNotEmpty)
                .join(', ') ??
            '';
        return CalendarResult(
          success: false,
          error: msg.isNotEmpty ? msg : _l10n.calendarAddFailedGeneric,
        );
      }
      return const CalendarResult(success: true);
    } catch (e) {
      return CalendarResult(success: false, error: e.toString());
    }
  }

  Future<CalendarResult> _addEventToAppleCalendar(
    CalendarEventModel model,
  ) async {
    try {
      final syncedIds = await _iosCalendarChannel.invokeListMethod<String>(
        'syncEvents',
        {
          'events': [
            {
              'id': model.appEventId,
              'title': model.title,
              'description': model.description,
              'location': model.location,
              'startDate': model.startDate.millisecondsSinceEpoch,
              'endDate': model.endDate.millisecondsSinceEpoch,
            },
          ],
        },
      );
      final success = syncedIds?.contains(model.appEventId) ?? false;
      return CalendarResult(
        success: success,
        error: success ? null : _l10n.calendarAppleAddFailed,
      );
    } on PlatformException catch (error) {
      return CalendarResult(
        success: false,
        error: error.message ?? _l10n.calendarAppleAddFailed,
      );
    }
  }

  Future<bool> isAdded(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefPrefix$eventId') ?? false;
  }

  Future<void> markAdded(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$eventId', true);
  }

  Future<String?> _findWritableCalendarId() async {
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess || result.data == null) return null;

    final writable = result.data!
        .where((c) => !(c.isReadOnly ?? true))
        .toList();
    if (writable.isEmpty) return null;

    if (Platform.isAndroid) {
      final google = writable.firstWhereOrNull(
        (c) => c.accountType?.toLowerCase().contains('google') == true,
      );
      if (google != null) return google.id;
    }

    return writable.first.id;
  }

  Future<bool> _isDuplicate(String calId, CalendarEventModel model) async {
    try {
      _initTz();
      final local = tz.local;
      final params = dc.RetrieveEventsParams(
        startDate: tz.TZDateTime.from(
          model.startDate.subtract(const Duration(minutes: 1)),
          local,
        ),
        endDate: tz.TZDateTime.from(
          model.endDate.add(const Duration(minutes: 1)),
          local,
        ),
      );
      final result = await _plugin.retrieveEvents(calId, params);
      if (!result.isSuccess || result.data == null) return false;

      final startMs = tz.TZDateTime.from(
        model.startDate,
        local,
      ).millisecondsSinceEpoch;
      return result.data!.any(
        (e) =>
            e.title == model.title &&
            e.start?.millisecondsSinceEpoch == startMs,
      );
    } catch (_) {
      return false;
    }
  }

  CalendarPermissionState _fromStatus(ph.PermissionStatus status) =>
      switch (status) {
        ph.PermissionStatus.granted => CalendarPermissionState.granted,
        ph.PermissionStatus.limited => CalendarPermissionState.granted,
        ph.PermissionStatus.denied => CalendarPermissionState.denied,
        ph.PermissionStatus.permanentlyDenied =>
          CalendarPermissionState.permanentlyDenied,
        ph.PermissionStatus.restricted => CalendarPermissionState.restricted,
        _ => CalendarPermissionState.unknown,
      };

  CalendarPermissionState _fromIosStatus(String? status) => switch (status) {
    'authorized' || 'writeOnly' => CalendarPermissionState.granted,
    'denied' => CalendarPermissionState.permanentlyDenied,
    'restricted' => CalendarPermissionState.restricted,
    'notDetermined' => CalendarPermissionState.denied,
    _ => CalendarPermissionState.unknown,
  };
}
