import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/screens/feed_screen.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/widgets/home_design.dart';

/// Pins the load-bearing claim behind guest mode: because guest mode never
/// calls `FeedV2Controller.loadFirstPage`, `hasLoadedFirstPage` stays false and
/// every rail in FeedScreen falls through to the in-memory registries
/// (`newsPosts`, `events`, `clubs`, `peopleService.cachedPeople`) — the pre-v2
/// path the screen still keeps for exactly this case. That is where the seed
/// world lives, so the whole feed renders with no screen changes and no network.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('guest_feed_render_');
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
    seedGuestWorld();
    authService.enterGuestSession();
  });

  tearDown(() async {
    await authService.logout();
    await localeService.setLanguage('en');
  });

  testWidgets('the guest feed renders seeded content with no backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FeedScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    // Post cards from the seeded world, not an empty state and not an error.
    expect(find.byType(HomeFeedPostCard), findsWidgets);
    expect(find.byKey(const ValueKey('feed-v2-initial-retry')), findsNothing);

    // Club names are proper nouns and are not localized, so they are a stable
    // thing to assert the seed world actually reached the screen.
    expect(find.textContaining('Debate Society'), findsWidgets);
  });

  testWidgets('the guest feed survives a language flip', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FeedScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(HomeFeedPostCard), findsWidgets);

    await localeService.setLanguage('tr');
    await tester.pump(const Duration(milliseconds: 700));

    // Still a populated feed: the locale listener rebuilt the seeded rows
    // under stable ids rather than emptying them.
    expect(find.byType(HomeFeedPostCard), findsWidgets);
    expect(find.textContaining('Debate Society'), findsWidgets);
  });
}
