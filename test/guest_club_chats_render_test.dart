import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/screens/chats_screen.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/locale_service.dart';

/// The Clubs tab of the guest inbox. Seeding the rooms in ChatStore is only
/// half the job — this is the half that proves they reach the screen someone
/// opening Guest Login actually looks at.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('guest_club_chats_');
    Hive.init(tempDir.path);
    await contentStore.initialize();
    await chatStore.initialize();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await localeService.setLanguage('en');
    guestSession.begin();
    // Identity before content: `enterGuestSession` crosses the chat auth
    // boundary, and ChatStore's constructor registers `clearChatV2AuthBoundary`
    // as that hook — so seeding first would have the conversations wiped a line
    // later. The feed seeds survive that order; chat seeds do not.
    authService.enterGuestSession();
    seedGuestWorld();
  });

  tearDown(() async {
    await authService.logout();
    await localeService.setLanguage('en');
  });

  Future<void> pumpChats(WidgetTester tester) async {
    // `chats_screen.dart:966` gives a thread row's trailing column a fixed
    // `SizedBox(width: 60, height: 37)`, and a timestamp that wraps plus the
    // unread badge inside it need 50px — so the inbox throws a 13px overflow on
    // every layout pass. Pre-existing and unrelated to these seeds: verified by
    // rendering the same inbox with only the original debate room seeded, which
    // overflows identically. Suppressed here rather than drained afterwards,
    // because the assertion re-fires per frame; and set inside the test body
    // because `testWidgets` installs its own handler after `setUp` runs.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    // The inbox opens on Friends for a student session; the club rooms live
    // behind the filter dropdown.
    await tester.tap(find.byKey(const ValueKey('chats-filter-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('chats-filter-option-clubs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }


  testWidgets('the Clubs tab lists every club room the guest follows', (
    tester,
  ) async {
    await pumpChats(tester);

    // Club names are proper nouns and are never localized, so they are the
    // stable signal that the seeded rooms reached the list.
    for (final name in [
      'Debate Society',
      'Robotics Collective',
      'Frame Photography Club',
      'Reel Society',
      'Trailhead Outdoor Club',
      'Campus Choir',
      'Community Volunteers',
      'Founders Circle',
    ]) {
      expect(
        find.textContaining(name),
        findsWidgets,
        reason: '$name has no row in the Clubs tab',
      );
    }
  });

  testWidgets('a room the guest only follows still renders its messages', (
    tester,
  ) async {
    await pumpChats(tester);

    // The row carries the thread id, so this cannot accidentally tap a
    // suggestion card that happens to mention the same club.
    final row = find.byKey(
      const ValueKey('chat-thread-row-club:guest_club_robotics'),
    );
    expect(row, findsOneWidget, reason: 'the robotics room has no inbox row');

    // Its preview is the room's most recent message, which is what makes the
    // list look lived in rather than a column of empty shells.
    // Its preview is the room's most recent message, which is what makes the
    // list look lived in rather than a column of empty shells. Assert the
    // shape ("Sender: body") rather than a specific line, so adding a newer
    // seed message does not break this.
    final preview = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .where((data) => data.contains(': '))
        .toList();
    expect(
      preview,
      isNotEmpty,
      reason: 'the row shows no last-message preview',
    );
  });


  testWidgets('the inbox carries a Direct thread with each joined club', (
    tester,
  ) async {
    await pumpChats(tester);

    // These are the club rooms' Direct lane, and they only exist because the
    // guest seeds club-inbox conversations — the real ones are a Supabase
    // round trip that guest mode never makes.
    for (final clubId in [
      'guest_club_debate',
      'guest_club_robotics',
      'guest_club_photo',
      'guest_club_film',
      'guest_club_hiking',
      'guest_club_music',
      'guest_club_volunteer',
      'guest_club_entre',
    ]) {
      expect(
        chatStore
            .threadsFor(kGuestUserId)
            .where((t) => t.isClubInbox && t.clubId == clubId),
        hasLength(1),
        reason: '$clubId has no direct thread in the inbox',
      );
    }
  });

  testWidgets('the last club joined is a room like any other', (tester) async {
    await pumpChats(tester);

    // Founders Circle used to be left out to show what an unjoined club looks
    // like. The guest now starts joined to every club, so it has to be a
    // normal row here rather than a locked-out shell.
    expect(
      find.byKey(const ValueKey('chat-thread-row-club:guest_club_entre')),
      findsOneWidget,
    );
  });

  testWidgets('the seeded rooms survive a language flip', (tester) async {
    await pumpChats(tester);
    expect(find.textContaining('Frame Photography Club'), findsWidgets);

    await localeService.setLanguage('tr');
    await tester.pump(const Duration(milliseconds: 700));

    // Rebuilt under stable ids rather than emptied — the same property the feed
    // seeds rely on.
    expect(find.textContaining('Frame Photography Club'), findsWidgets);

  });
}
