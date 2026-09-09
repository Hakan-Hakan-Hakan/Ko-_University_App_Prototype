import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/screens/club_insights_screen.dart';
import 'package:flutter_application_1/screens/club_members_screen.dart';
import 'package:flutter_application_1/screens/club_profile_screen.dart';
import 'package:flutter_application_1/screens/event_attendee_list_screen.dart';
import 'package:flutter_application_1/screens/event_detail_screen.dart';
import 'package:flutter_application_1/screens/notifications_screen.dart';
import 'package:flutter_application_1/screens/post_detail_screen.dart';
import 'package:flutter_application_1/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/screens/student_activity_screen.dart';
import 'package:flutter_application_1/screens/user_profile_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/widgets/guest_notice_dialog.dart';

/// Opens every detail screen a guest can navigate to and asserts each one
/// builds without throwing.
///
/// This exists because the event page used to die on a red screen: the seeded
/// `accentColorHex` carried a `#`, and `EventDetailScreen` parsed that column
/// with `int.parse('FF$hex', radix: 16)`. Nothing in the app writes that
/// column, so nothing normalised it either. One bad field in seed data (or in
/// a real Supabase row) took down a whole page, and only opening the page
/// found it — hence a smoke test over all of them rather than one.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('guest_screen_smoke_');
    Hive.init(tempDir.path);
    await contentStore.initialize();
    await chatStore.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await localeService.setLanguage('en');
    guestSession.begin();
    // The order `_onGuestLogin` uses: identity before content.
    authService.enterGuestSession();
    seedGuestWorld();
  });

  tearDown(() async {
    await authService.logout();
  });

  /// Pumps [child] the way the app does — inside a ProviderScope, since the
  /// avatars are Riverpod consumers — and fails on any thrown exception.
  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    // Collect each error as it is reported. `takeException` aggregates several
    // into one opaque "Multiple exceptions (N)" wrapper, which would hide a
    // real defect sitting among a handful of layout warnings.
    final errors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 44 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    // Two settles: the first frame kicks off the screens' post-frame loads.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    tester.takeException();

    // `flutter_test` substitutes a fixed-width fallback font, in which every
    // glyph is a full em wide, so a label that fits the real typeface can
    // still overflow here. Two rows in shared widgets do exactly that —
    // `_AdminAttendees`, and rsvp_button's `compact-attending` chip once the
    // viewer is attending — and neither overflows with real fonts on a
    // simulator (`integration_test/guest_joyride_drive_test.dart` opens the
    // event page and asserts no exception). So overflows are tolerated here
    // and anything else fails, which is what this file exists to catch.
    final real = errors
        .where((error) => !error.contains('overflowed'))
        .toList();
    expect(
      real,
      isEmpty,
      reason: '${child.runtimeType} threw ${real.length} non-layout error(s)',
    );
  }

  const accent = Color(0xFF8C1D40);

  testWidgets('event detail opens for a seeded event', (tester) async {
    final event = events.firstWhere((e) => e.id == 'guest_event_1');
    await pumpScreen(tester, EventDetailScreen(event: event, color: accent));

    expect(find.textContaining('Parliamentary'), findsWidgets);
    // The RSVP count survives the attendee fetch: `fetchEventAttendees`
    // answers from the seed world rather than returning an empty list, which
    // the page would otherwise treat as "nobody is going".
    expect(supabaseEventRsvpCounts[event.id], event.attendeeUserIds.length);
  });

  testWidgets('event detail opens for every seeded event', (tester) async {
    for (final event in List.of(events)) {
      await pumpScreen(tester, EventDetailScreen(event: event, color: accent));
    }
  });

  testWidgets('the organiser view opens for the guest own club event', (
    tester,
  ) async {
    final event = events.firstWhere((e) => e.clubId == kGuestBoardClubId);
    await pumpScreen(
      tester,
      ClubEventAdminScreen(event: event, accent: accent),
    );
  });

  testWidgets('the attendee list opens', (tester) async {
    final event = events.firstWhere((e) => e.id == 'guest_event_1');
    await pumpScreen(
      tester,
      EventAttendeeListScreen(event: event, color: accent),
    );
  });

  testWidgets('post detail opens for every seeded post', (tester) async {
    for (final post in List.of(newsPosts)) {
      await pumpScreen(tester, PostDetailScreen(post: post, clubColor: accent));
    }
  });

  testWidgets('club profile opens for every seeded club', (tester) async {
    for (final club in List.of(clubs)) {
      await pumpScreen(tester, ClubProfileScreen(club: club, color: accent));
    }
  });

  testWidgets('club members opens', (tester) async {
    final club = clubForId(kGuestBoardClubId)!;
    await pumpScreen(
      tester,
      ClubMembersScreen(club: club, myId: kGuestUserId),
    );
  });

  testWidgets('club insights opens for the club the guest helps run', (
    tester,
  ) async {
    final club = clubForId(kGuestBoardClubId)!;
    await pumpScreen(tester, ClubInsightsScreen(club: club, accent: accent));
  });

  testWidgets('another student profile opens', (tester) async {
    final other = users.firstWhere((u) => u.id != kGuestUserId);
    await pumpScreen(tester, UserProfileScreen(user: other));
  });

  testWidgets('saved items opens', (tester) async {
    await pumpScreen(tester, const SavedPostsScreen());
  });

  testWidgets('notifications opens', (tester) async {
    await pumpScreen(tester, const NotificationsScreen());
  });

  testWidgets('the activity history opens', (tester) async {
    await pumpScreen(
      tester,
      StudentActivityScreen(
        userId: kGuestUserId,
        studentName: guestSessionUser().name,
        isOwnProfile: true,
      ),
    );
  });

  testWidgets('the demo notice says it is sample data, in both languages', (
    tester,
  ) async {
    for (final language in const ['en', 'tr']) {
      await localeService.setLanguage(language);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGuestNoticeDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('guest-notice-dialog')),
        findsOneWidget,
        reason: 'no notice in $language',
      );
      expect(find.text(S.guestNoticeTitle), findsOneWidget);
      expect(find.text(S.guestNoticeBody), findsOneWidget);
      // It has to say both that the data is fake and that nothing is kept.
      expect(find.text(S.guestNoticeFooter), findsOneWidget);

      // A single acknowledge button, and the barrier does not dismiss it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('guest-notice-dialog')),
        findsOneWidget,
        reason: 'tapping outside dismissed the notice in $language',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('guest-notice-accept')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('guest-notice-dialog')),
        findsNothing,
      );
    }
    await localeService.setLanguage('en');
  });
}
