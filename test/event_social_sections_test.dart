import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/app_admin.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/screens/event_detail_screen.dart';
import 'package:flutter_application_1/screens/this_week_screen.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/people_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_application_1/widgets/user_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who a student is allowed to see on an event.
///
/// The rule itself is unit-tested in `event_attendee_visibility_test.dart`;
/// these cover the rendering. They go through the events list rather than the
/// event detail because `EventDetailScreen` reads its attendees from Supabase
/// and treats "no client" as "nobody is going", so a widget test never gets a
/// populated attending card out of it.
void main() {
  late Directory tempDir;
  late Event event;
  late List<Club> originalClubs;
  late List<User> originalUsers;
  late List<Event> originalEvents;

  const clubId = 'event-social-club';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('event_social_test_');
    Hive.init(tempDir.path);
    // authService.logout() clears the session store, which needs the plugin.
    SharedPreferences.setMockInitialValues(const {});
  });

  setUp(() {
    originalClubs = List<Club>.from(clubs);
    originalUsers = List<User>.from(users);
    originalEvents = List<Event>.from(events);
    clubs.clear();
    users.clear();
    events.clear();
    peopleService.clearRemoteCaches();

    clubs.add(
      Club(
        id: clubId,
        name: 'Campus Creators',
        description: 'Fixture club',
        adminUserIds: const [clubId],
      ),
    );

    expect(
      authService.signUp('Current Student', 'event.social@ku.edu.tr', '135790'),
      isTrue,
    );

    users.addAll([
      _user('attendee-1', 'Ceren Levent'),
      _user('attendee-2', 'Zeynep Arslan'),
      _user('attendee-3', 'Tolga Kurt'),
      _user('attendee-4', 'Mina Demir'),
      _user('friend-1', 'Ece Yılmaz'),
      _user('friend-2', 'Can Kaya'),
      _user('friend-3', 'Selin Aksoy'),
    ]);
    userState.replaceFollowedUsers(const ['attendee-1', 'attendee-2']);

    final start = DateTime.now().add(const Duration(days: 2));
    event = Event(
      id: 'event-social-sections',
      clubId: clubId,
      title: 'Campus Futures Forum',
      description: 'A student-led conversation about the future of campus.',
      dateTime: start,
      endTime: start.add(const Duration(hours: 2)),
      location: 'Student Center',
      attendeeUserIds: const [
        'attendee-1',
        'attendee-2',
        'attendee-3',
        'attendee-4',
      ],
    );
    events.add(event);
  });

  tearDown(() {
    authService.logout();
    peopleService.clearRemoteCaches();
    userState.replaceFollowedUsers(const []);
    clubs
      ..clear()
      ..addAll(originalClubs);
    users
      ..clear()
      ..addAll(originalUsers);
    events
      ..clear()
      ..addAll(originalEvents);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Seeds the follower half of the follow graph. In the app it only ever
  /// arrives from Supabase, so a test that omits it exercises the one-way
  /// fallback instead of the mutual filter.
  void seedFollowers(Iterable<String> followerIds) {
    peopleService.seedFeedSuggestions(const <User>[], followerIds: followerIds);
  }

  /// Mounting the screen runs the lazy content loader, which wipes the
  /// people-service caches the first time it sees a new auth scope — so the
  /// follower half has to be seeded after that first frame, not before.
  Future<void> pumpEventsList(
    WidgetTester tester, {
    Iterable<String> followers = const [],
  }) async {
    await tester.pumpWidget(_app(const ThisWeekScreen()));
    await tester.pump();
    if (followers.isEmpty) return;
    seedFollowers(followers);
    await tester.pumpWidget(_app(const ThisWeekScreen()));
    await tester.pump();
  }

  group('who is going', () {
    testWidgets('a student only sees attendees they follow each other with', (
      tester,
    ) async {
      await pumpEventsList(tester, followers: const ['attendee-1']);

      // attendee-2 is followed one way; attendee-3 and -4 not at all.
      expect(find.text('1 going'), findsOneWidget);
      // Never the real turnout of four.
      expect(find.text('4 going'), findsNothing);
      expect(find.byType(UserAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one-way follows stand in until the follower half loads', (
      tester,
    ) async {
      // No seedFollowers: offline, or before startup hydration lands.
      await pumpEventsList(tester);

      expect(find.text('2 going'), findsOneWidget);
      expect(find.byType(UserAvatar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row goes away when no one they follow is going', (
      tester,
    ) async {
      userState.replaceFollowedUsers(const []);

      await pumpEventsList(tester);

      expect(find.textContaining('going'), findsNothing);
      expect(find.byType(UserAvatar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('another club gets the real headcount but no faces', (
      tester,
    ) async {
      clubs.add(
        Club(
          id: 'other-club',
          name: 'Other Collective',
          description: 'Fixture club',
          adminUserIds: const ['other-club'],
        ),
      );
      authService.setClubAdmin(
        AppAdmin(
          id: 'other-club',
          name: 'Other Collective',
          email: 'other@ku.edu.tr',
          password: '',
        ),
      );

      await pumpEventsList(tester);

      expect(find.text('4 going'), findsOneWidget);
      expect(find.byType(UserAvatar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hosting club still sees everyone', (tester) async {
      authService.setClubAdmin(
        AppAdmin(
          id: clubId,
          name: 'Campus Creators',
          email: 'creators@ku.edu.tr',
          password: '',
        ),
      );

      await pumpEventsList(tester);

      expect(find.text('4 going'), findsOneWidget);
      // The stack caps at three faces, which is the pre-existing design.
      expect(find.byType(UserAvatar), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('bring friends', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(EventDetailScreen(event: event, color: const Color(0xFF9E2045))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('invite action updates the row state', (tester) async {
      await pumpDetail(tester);

      await tester.tap(find.byKey(const ValueKey('event-invite-friend-1')));
      // The invited slot is swapped out on a 620ms delay; let it fire so the
      // timer does not outlive the tree.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
    });

    testWidgets('Send to More Friends opens the share sheet', (tester) async {
      await pumpDetail(tester);

      await tester.tap(find.text('Send to More Friends'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('event-share-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event-share-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

User _user(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@ku.edu.tr',
  password: '',
  role: 'student',
  subscribedClubIds: const [],
);

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);
