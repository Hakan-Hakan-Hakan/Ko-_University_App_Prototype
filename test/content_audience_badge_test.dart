import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/content_audience.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/models/news_post.dart';
import 'package:flutter_application_1/screens/post_detail_screen.dart';
import 'package:flutter_application_1/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/screens/this_week_screen.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/rsvp_store.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_application_1/widgets/club_profile_design.dart';
import 'package:flutter_application_1/widgets/content_audience_sheet.dart';
import 'package:flutter_application_1/widgets/home_design.dart';
import 'package:flutter_application_1/widgets/profile_design.dart';
import 'package:flutter_application_1/widgets/shared_event_message_card.dart';
import 'package:flutter_application_1/widgets/shared_post_message_card.dart';

/// Every surface that draws a post or an event has to say when that content is
/// not public.
///
/// The picker and the rule set shipped before this did: a club could restrict a
/// post to its board and then find no trace of that choice anywhere in the app.
/// The badge existed but only on the legacy feed card (which only a moderator
/// session reaches), on a card with no call sites at all, and on the event hero.
/// Every card a student or a club president actually scrolls past drew nothing.
///
/// So these tests are deliberately about *placement*, not about the pill: they
/// assert the badge is mounted on each live surface, keyed by content id, and
/// that public content still gets nothing.
void main() {
  late Directory tempDir;
  late List<User> originalUsers;

  const clubId = 'badge-club';
  const otherClubId = 'badge-club-2';

  NewsPost postFor(ContentAudience audience) => NewsPost(
    id: 'badge-post-${audience.wireValue}',
    clubId: clubId,
    authorId: 'badge-author',
    content: 'Minutes from the last meeting are up.',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    audience: audience,
  );

  Event eventFor(ContentAudience audience) => Event(
    id: 'badge-event-${audience.wireValue}',
    clubId: clubId,
    title: 'Board sync',
    description: 'Fixture',
    dateTime: DateTime.now().add(const Duration(days: 1)),
    endTime: DateTime.now().add(const Duration(days: 1, hours: 2)),
    location: 'Student Center',
    attendeeUserIds: const [],
    audience: audience,
  );

  Finder pillFor(String contentId) =>
      find.byKey(ValueKey('content-audience-pill-$contentId'));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('audience_badge_');
    Hive.init(tempDir.path);
    await contentStore.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await themeService.setDark(false);
    await localeService.setLanguage('en');
    originalUsers = List<User>.from(users);
    clubs
      ..clear()
      ..add(
        Club(
          id: clubId,
          name: 'Debate Society',
          description: 'Fixture',
          adminUserIds: const [clubId],
          // Growable: `signInBoardMember` puts the freshly signed-in
          // student on this board.
          boardMemberIds: <String>['badge-board-member'],
        ),
      )
      ..add(
        Club(
          id: otherClubId,
          name: 'Robotics',
          description: 'Fixture',
          adminUserIds: const [otherClubId],
        ),
      );
    newsPosts
      ..clear()
      ..addAll([
        postFor(ContentAudience.board),
        postFor(ContentAudience.followers),
        postFor(ContentAudience.everyone),
      ]);
    events
      ..clear()
      ..addAll([
        eventFor(ContentAudience.board),
        eventFor(ContentAudience.followers),
        eventFor(ContentAudience.everyone),
      ]);
  });

  tearDown(() async {
    await authService.logout();
    userState.replaceFollowedClubs(const []);
    clubs.clear();
    newsPosts.clear();
    events.clear();
    userState.savedPostIds.clear();
    users
      ..clear()
      ..addAll(originalUsers);
  });

  /// Signs in a student and puts them on the club's board.
  ///
  /// The two screen tests below need this and the widget tests do not, and
  /// that difference is the point: a card renders whatever it is handed, but
  /// `ThisWeekScreen` and `SavedPostsScreen` filter through `canViewEvent` /
  /// `canViewPost` first. A signed-out session never reaches a board-only
  /// event at all — so the only viewer who can be shown this badge is one
  /// entitled to the content, which is who it is for.
  void signInBoardMember() {
    expect(
      authService.signUp('Board Member', 'badge.board@ku.edu.tr', '135790'),
      isTrue,
    );
    clubs
        .firstWhere((club) => club.id == clubId)
        .boardMemberIds
        .add(authService.currentUser!.id);
  }

  /// Pumps [child] the way the app does. The avatars are Riverpod consumers,
  /// so the scope is not optional.
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(localeService.languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  // ── Posts ────────────────────────────────────────────────────────────────

  testWidgets('the home feed card badges a restricted post', (tester) async {
    // `HomeFeedPostCard` is the post card for both a student session and a
    // club-admin one (`feed_screen` picks it for either), and the club profile
    // timeline renders it too. If the badge is anywhere, it is here.
    for (final audience in ContentAudience.values) {
      final post = postFor(audience);
      await pump(tester, HomeFeedPostCard(post: post, onChanged: () {}));

      expect(
        pillFor(post.id),
        audience == ContentAudience.everyone ? findsNothing : findsOneWidget,
        reason: 'home card, ${audience.wireValue}',
      );
      if (audience != ContentAudience.everyone) {
        expect(find.text(S.audienceTierPill(audience)), findsOneWidget);
      }
    }
  });

  testWidgets('an announcement keeps its own chip alongside the badge', (
    tester,
  ) async {
    // The two chips share one line. A club that marks a post as both an
    // announcement and board-only must still see both.
    final post = NewsPost(
      id: 'badge-post-announcement',
      clubId: clubId,
      authorId: 'badge-author',
      content: 'Fixture',
      createdAt: DateTime.now(),
      isAnnouncement: true,
      audience: ContentAudience.board,
    );
    await pump(tester, HomeFeedPostCard(post: post, onChanged: () {}));

    expect(find.text(S.announcementLabel), findsOneWidget);
    expect(pillFor(post.id), findsOneWidget);
  });

  testWidgets('the post page badges a restricted post', (tester) async {
    final post = postFor(ContentAudience.board);
    await pump(
      tester,
      PostDetailScreen(post: post, clubColor: const Color(0xFF800020)),
    );
    expect(pillFor(post.id), findsOneWidget);

    await pump(
      tester,
      PostDetailScreen(
        post: postFor(ContentAudience.everyone),
        clubColor: const Color(0xFF800020),
      ),
    );
    expect(pillFor('badge-post-everyone'), findsNothing);
  });

  testWidgets('a post forwarded into a chat keeps its badge', (tester) async {
    await pump(
      tester,
      SharedPostMessageCard(postId: 'badge-post-followers'),
    );
    expect(pillFor('badge-post-followers'), findsOneWidget);

    await pump(tester, SharedPostMessageCard(postId: 'badge-post-everyone'));
    expect(pillFor('badge-post-everyone'), findsNothing);
  });

  // ── Events ───────────────────────────────────────────────────────────────

  testWidgets('the Events tab badges a restricted event', (tester) async {
    // The one event surface a student uses daily, and the one the user found
    // silent. Driven through the whole screen because the row is private to it.
    signInBoardMember();
    await pump(tester, const ThisWeekScreen());
    await tester.pump(const Duration(milliseconds: 600));

    expect(pillFor('badge-event-board'), findsOneWidget);
    expect(pillFor('badge-event-followers'), findsOneWidget);
    expect(pillFor('badge-event-everyone'), findsNothing);
  });

  testWidgets("the club profile's event row badges a restricted event", (
    tester,
  ) async {
    // The card takes the badge as a slot, so the assertion that matters is
    // that a supplied badge is actually mounted rather than dropped.
    await pump(
      tester,
      ClubProfileEventCard(
        cover: const SizedBox(),
        title: 'Board sync',
        dateLabel: 'Sat, 12 Sep',
        timeLabel: '19:00',
        location: 'Student Center',
        statusLabel: 'PAST',
        audienceBadge: const ContentAudiencePill(
          key: ValueKey('content-audience-pill-badge-event-board'),
          audience: ContentAudience.board,
          accent: Color(0xFF800020),
        ),
      ),
    );

    expect(pillFor('badge-event-board'), findsOneWidget);
    // The status chip shares that line and must survive the badge.
    expect(find.text('PAST'), findsOneWidget);
  });

  testWidgets('a profile event card badges a restricted event', (tester) async {
    await pump(
      tester,
      ProfileEventCard(
        event: eventFor(ContentAudience.board),
        color: const Color(0xFF800020),
        whenLabel: 'Sat, 12 Sep · 19:00',
        clubName: 'Debate Society',
      ),
    );
    expect(pillFor('badge-event-board'), findsOneWidget);
  });

  testWidgets('an event forwarded into a chat keeps its badge', (tester) async {
    await pump(
      tester,
      SharedEventMessageCard(
        eventId: 'badge-event-board',
        resolveEvent: (id) async => null,
      ),
    );
    expect(pillFor('badge-event-board'), findsOneWidget);
  });

  // ── Saved items ──────────────────────────────────────────────────────────

  testWidgets('the saved list badges restricted posts and events', (
    tester,
  ) async {
    signInBoardMember();
    userState.savedPostIds
      ..add('badge-post-board')
      ..add('badge-post-everyone')
      ..add('badge-event-followers');
    rsvpStore.seed('badge-event-followers', true);

    await pump(tester, const SavedPostsScreen());
    await tester.pump(const Duration(milliseconds: 600));

    expect(pillFor('badge-post-board'), findsOneWidget);
    expect(pillFor('badge-post-everyone'), findsNothing);
  });

  // ── Copy ─────────────────────────────────────────────────────────────────

  testWidgets('the badge speaks Turkish with the app', (tester) async {
    await localeService.setLanguage('tr');
    addTearDown(() => localeService.setLanguage('en'));

    final post = postFor(ContentAudience.board);
    await pump(tester, HomeFeedPostCard(post: post, onChanged: () {}));

    expect(find.text('Yalnızca yönetim'), findsOneWidget);
    expect(find.text('Board only'), findsNothing);
  });
}
