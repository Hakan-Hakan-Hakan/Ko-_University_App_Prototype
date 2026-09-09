import 'dart:io';

import 'package:flutter_application_1/models/app_admin.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/event_attendee_visibility.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/people_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The attendee list is not a public guest list. These cover the three
/// audiences [attendeeVisibilityFor] distinguishes: the hosting club, a
/// student, and everyone else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<Club> originalClubs;
  late List<User> originalUsers;

  const clubId = 'attendee-visibility-club';
  const attendeeIds = ['mutual-1', 'oneway-2', 'stranger-3', 'stranger-4'];

  final event = Event(
    id: 'attendee-visibility-event',
    clubId: clubId,
    title: 'Campus Futures Forum',
    description: 'Fixture',
    dateTime: DateTime.now().add(const Duration(days: 3)),
    endTime: DateTime.now().add(const Duration(days: 3, hours: 2)),
    location: 'Student Center',
    attendeeUserIds: const [...attendeeIds],
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('attendee_visibility_');
    Hive.init(tempDir.path);
  });

  setUp(() {
    originalClubs = List<Club>.from(clubs);
    originalUsers = List<User>.from(users);
    clubs.add(
      Club(
        id: clubId,
        name: 'Rooftop Collective',
        description: 'Fixture',
        adminUserIds: const [clubId],
      ),
    );
    peopleService.clearRemoteCaches();
    userState.replaceFollowedUsers(const []);
  });

  tearDown(() async {
    await authService.logout();
    peopleService.clearRemoteCaches();
    userState.replaceFollowedUsers(const []);
    clubs
      ..clear()
      ..addAll(originalClubs);
    users
      ..clear()
      ..addAll(originalUsers);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Signs a fresh student in. Each call needs its own address because
  /// `signUp` refuses a duplicate.
  String signInStudent(String slug) {
    expect(
      authService.signUp('Student $slug', '$slug@ku.edu.tr', '135790'),
      isTrue,
    );
    return authService.currentUser!.id;
  }

  /// Seeds the follower half of the graph, which only ever arrives from
  /// Supabase in the app.
  void seedFollowers(Iterable<String> followerIds) {
    peopleService.seedFeedSuggestions(const <User>[], followerIds: followerIds);
  }

  group('student', () {
    test('sees only the attendees they follow each other with', () {
      signInStudent('mutual-only');
      userState.replaceFollowedUsers(const ['mutual-1', 'oneway-2']);
      seedFollowers(const ['mutual-1']);

      final visibility = attendeeVisibilityFor(
        event,
        attendeeIds: attendeeIds,
        totalCount: 47,
      );

      expect(visibility.visibleIds, const ['mutual-1']);
      // The headcount describes the faces, never the real turnout.
      expect(visibility.count, 1);
      expect(visibility.showsNames, isTrue);
      // Drives the "Friends going" framing and drops every headcount.
      expect(visibility.friendsOnly, isTrue);
    });

    test('falls back to one-way follows when the follower half is missing', () {
      signInStudent('offline-graph');
      userState.replaceFollowedUsers(const ['mutual-1', 'oneway-2']);
      // No seedFollowers: offline, and before startup hydration lands.

      final visibility = attendeeVisibilityFor(event, attendeeIds: attendeeIds);

      expect(visibility.visibleIds, const ['mutual-1', 'oneway-2']);
      expect(visibility.count, 2);
    });

    test('never widens past people the viewer follows', () {
      signInStudent('follower-not-followed');
      userState.replaceFollowedUsers(const []);
      // stranger-3 follows the viewer, but the viewer does not follow back.
      seedFollowers(const ['stranger-3']);

      final visibility = attendeeVisibilityFor(event, attendeeIds: attendeeIds);

      expect(visibility.visibleIds, isEmpty);
      expect(visibility.count, 0);
    });

    test('counts their own RSVP', () {
      final selfId = signInStudent('self-rsvp');
      userState.replaceFollowedUsers(const ['mutual-1']);
      seedFollowers(const ['mutual-1']);

      final visibility = attendeeVisibilityFor(
        event,
        attendeeIds: [selfId, ...attendeeIds],
      );

      expect(visibility.visibleIds, [selfId, 'mutual-1']);
      expect(visibility.count, 2);
    });
  });

  test('the hosting club keeps the full list and the real total', () {
    authService.setClubAdmin(
      AppAdmin(
        id: clubId,
        name: 'Rooftop Collective',
        email: 'rooftop@ku.edu.tr',
        password: '',
      ),
    );

    final visibility = attendeeVisibilityFor(
      event,
      attendeeIds: attendeeIds,
      totalCount: 47,
    );

    expect(visibility.visibleIds, attendeeIds);
    expect(visibility.count, 47);
    expect(visibility.showsNames, isTrue);
    // A guest list, not a friends list: it keeps the "N attending" line.
    expect(visibility.friendsOnly, isFalse);
  });

  test('another club gets the headcount and no names', () {
    const otherClubId = 'some-other-club';
    clubs.add(
      Club(
        id: otherClubId,
        name: 'Other Collective',
        description: 'Fixture',
        adminUserIds: const [otherClubId],
      ),
    );
    authService.setClubAdmin(
      AppAdmin(
        id: otherClubId,
        name: 'Other Collective',
        email: 'other@ku.edu.tr',
        password: '',
      ),
    );

    final visibility = attendeeVisibilityFor(
      event,
      attendeeIds: attendeeIds,
      totalCount: 47,
    );

    expect(visibility.visibleIds, isEmpty);
    expect(visibility.count, 47);
    expect(visibility.showsNames, isFalse);
    expect(visibility.friendsOnly, isFalse);
  });

  test('a session with no student identity gets no names', () {
    final visibility = attendeeVisibilityFor(event, attendeeIds: attendeeIds);

    expect(visibility.visibleIds, isEmpty);
    expect(visibility.count, attendeeIds.length);
    expect(visibility.showsNames, isFalse);
  });
}
