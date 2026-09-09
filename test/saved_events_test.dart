import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/screens/this_week_screen.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/user_prefs_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saving an event from the Events tab has to reach Saved items and survive a
/// restart. It used to write a session-only set inside `ThisWeekScreen` that
/// nothing else could read.
void main() {
  late Directory tempDir;
  late List<Club> originalClubs;
  late List<Event> originalEvents;
  late List<User> originalUsers;
  late String userId;

  const clubId = 'saved-events-club';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('saved_events_');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues(const {});
    await userPrefsService.initialize();
  });

  setUp(() {
    originalClubs = List<Club>.from(clubs);
    originalEvents = List<Event>.from(events);
    originalUsers = List<User>.from(users);
    clubs.clear();
    events.clear();
    users.clear();
    userState.savedPostIds.clear();

    clubs.add(
      Club(
        id: clubId,
        name: 'Campus Creators',
        description: 'Fixture club',
        adminUserIds: const [clubId],
      ),
    );

    expect(
      authService.signUp('Saver Student', 'saver@ku.edu.tr', '135790'),
      isTrue,
    );
    userId = authService.currentUser!.id;

    // Deliberately added out of date order, so a passing order assertion can
    // only come from the sort and not from insertion order.
    events.addAll([
      _event('ev-late', 'Closing Night', const Duration(days: 9)),
      _event('ev-soon', 'Opening Talk', const Duration(days: 2)),
      _event('ev-mid', 'Workshop Day', const Duration(days: 5)),
    ]);
  });

  tearDown(() {
    authService.logout();
    userState.savedPostIds.clear();
    clubs
      ..clear()
      ..addAll(originalClubs);
    events
      ..clear()
      ..addAll(originalEvents);
    users
      ..clear()
      ..addAll(originalUsers);
  });

  tearDownAll(() {
    // No Hive.close() here: this file opens the user_prefs box through
    // userPrefsService, and closing it waits on those writes forever — the
    // whole file then dies on the 12-minute suite timeout with every test
    // already green.
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('the Events tab save button writes the shared saved state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const ThisWeekScreen()));
    await tester.pump();

    final save = find.byKey(const ValueKey('event-save-ev-mid'));
    expect(save, findsOneWidget);
    expect(userState.isSaved('ev-mid'), isFalse);

    await tester.tap(save);
    await tester.pump();

    expect(userState.isSaved('ev-mid'), isTrue);
    // The card reflects it without a manual refresh.
    expect(
      find.descendant(of: save, matching: find.byIcon(Icons.bookmark_rounded)),
      findsOneWidget,
    );

    // Tapping again unsaves.
    await tester.tap(save);
    await tester.pump();
    expect(userState.isSaved('ev-mid'), isFalse);
  });

  testWidgets('the save survives a restart of the saved-state store', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const ThisWeekScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('event-save-ev-soon')));
    await tester.pump();
    // Let the write land before reading it back.
    await tester.pump(const Duration(milliseconds: 100));

    // Wipe the in-memory set the way a fresh launch would, then reload.
    userState.savedPostIds.clear();
    expect(userState.isSaved('ev-soon'), isFalse);

    userPrefsService.load(userId);
    expect(userState.isSaved('ev-soon'), isTrue);
  });

  testWidgets('Saved items lists saved events in chronological order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final id in ['ev-late', 'ev-soon', 'ev-mid']) {
      userState.toggleSave(id);
    }

    await tester.pumpWidget(_app(const SavedPostsScreen()));
    await tester.pump();

    // The screen opens on Posts; the second segment is Events.
    await tester.tap(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(SavedPostsScreen)),
        )!.eventsCountLabel(3),
      ),
    );
    await tester.pump();

    final soon = tester.getTopLeft(find.text('Opening Talk')).dy;
    final mid = tester.getTopLeft(find.text('Workshop Day')).dy;
    final late = tester.getTopLeft(find.text('Closing Night')).dy;
    expect(soon, lessThan(mid));
    expect(mid, lessThan(late));
  });

  testWidgets('a club session cannot save an event', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    authService.logout();

    await tester.pumpWidget(_app(const ThisWeekScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('event-save-ev-mid')));
    await tester.pump();

    expect(userState.isSaved('ev-mid'), isFalse);
  });
}

Event _event(String id, String title, Duration fromNow) {
  final start = DateTime.now().add(fromNow);
  return Event(
    id: id,
    clubId: 'saved-events-club',
    title: title,
    description: 'Fixture event',
    dateTime: start,
    endTime: start.add(const Duration(hours: 2)),
    location: 'Student Center',
    attendeeUserIds: const [],
  );
}

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);
