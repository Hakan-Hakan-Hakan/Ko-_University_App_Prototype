import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/onboarding/onboarding_service.dart';
import 'package:flutter_application_1/screens/main_nav_screen.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/hive_bootstrap.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/onboarding_intro_service.dart';
import 'package:flutter_application_1/services/personalization_service.dart';
import 'package:flutter_application_1/services/terms_acceptance_service.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/services/user_prefs_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_application_1/services/view_tracker.dart';
import 'package:flutter_application_1/widgets/home_design.dart';

/// Drives the Guest Login joyride end to end on a device:
///  A) the guest pill opens a populated app, with the tour on top
///  B) the seeded feed, events, search, chats and profile all render
///  C) logging out returns to the login screen and leaves nothing behind
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot() async {
    await hiveBootstrap.initialize();
    await notificationService.initialize();
    await userPrefsService.initialize();
    await contentStore.initialize();
    await chatStore.initialize();
    await viewTracker.initialize();
    await personalizationService.initialize();
    await themeService.initialize();
    await onboardingService.initialize();
    await termsAcceptanceService.initialize();
    await onboardingIntroService.initialize();
    await onboardingIntroService.markCompletedOnDevice();
    contentStore.applyToLists();
    await themeService.setDark(false);
    await localeService.setLanguage('en');
  }

  testWidgets('Guest Login opens a populated app and leaves nothing behind', (
    tester,
  ) async {
    await boot();

    // `main()` wraps MyApp in a ProviderScope; the avatars are Riverpod
    // consumers, so the driver has to do the same or every avatar in the app
    // builds an unbounded ErrorWidget.
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(minimumLaunchDuration: Duration.zero),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();

    if (find.text('Agree and continue').evaluate().isNotEmpty) {
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Agree and continue'));
      await tester.pump(const Duration(milliseconds: 700));
    }
    await binding.takeScreenshot('guest-01-login');

    // Nothing is seeded until the pill is pressed. The device may well have
    // real cached content in Hive already (bootstrap's `applyToLists`), which
    // is exactly the case `seedGuestWorld` has to clear out.
    expect(guestSession.isActive, isFalse);
    expect(newsPosts.where((p) => p.id.startsWith(kGuestIdPrefix)), isEmpty);

    // ── A) enter the joyride ──
    await tester.tap(find.byKey(const ValueKey<String>('landing-guest-login')));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    expect(guestSession.isActive, isTrue);
    expect(guestWorldIsSeeded, isTrue);
    expect(find.byType(MainNavScreen), findsOneWidget);
    // The guest is an ordinary student session, which is what keeps every
    // write affordance enabled.
    expect(authService.isStudentSession, isTrue);

    // The demo is spelled out before anything else, so a visitor cannot take
    // the seeded campus for the real one.
    expect(
      find.byKey(const ValueKey<String>('guest-notice-dialog')),
      findsOneWidget,
    );
    await binding.takeScreenshot('guest-02-demo-notice');
    await tester.tap(
      find.byKey(const ValueKey<String>('guest-notice-accept')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    await binding.takeScreenshot('guest-02b-tour-welcome');

    // The tour auto-runs. Dismiss it to get at the app underneath.
    for (final label in const [
      'Skip for now',
      'Skip',
      'Got it',
      'Done',
    ]) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tester.tap(find.text(label).first);
        await tester.pump(const Duration(milliseconds: 700));
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 700));

    // ── B) the seeded world renders ──
    await binding.takeScreenshot('guest-03-feed');
    expect(find.byType(HomeFeedPostCard), findsWidgets);
    // The device's own cached rows were replaced, not merged into the demo.
    expect(newsPosts.every((p) => p.id.startsWith(kGuestIdPrefix)), isTrue);
    expect(clubs.every((c) => c.id.startsWith(kGuestIdPrefix)), isTrue);

    // Walk the tabs by their visible labels, as the other nav drive tests do.
    Future<void> openTab(String label, String shot) async {
      final tab = find.text(label);
      if (tab.evaluate().isEmpty) return;
      await tester.tap(tab.first);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 600));
      await binding.takeScreenshot(shot);
    }

    await openTab('Events', 'guest-04-events');

    // Open an event. This is the page that used to die on a red screen: the
    // seeded accent hex carried a `#` and EventDetailScreen parsed the column
    // with `int.parse('FF$hex', radix: 16)`.
    final eventCard = find.textContaining('Parliamentary');
    if (eventCard.evaluate().isNotEmpty) {
      await tester.tap(eventCard.first);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 900));
      await binding.takeScreenshot('guest-04b-event-detail');
      expect(find.textContaining('Parliamentary'), findsWidgets);
      // With real fonts and a real viewport: no overflow, no error box.
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);

      // Not `pageBack()`: the event page draws its own floating back control,
      // so there is no CupertinoNavigationBarBackButton for it to find.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 900));
    }

    await openTab('Search', 'guest-05-search');
    await openTab('Chats', 'guest-06-chats');
    await openTab('Profile', 'guest-07-profile');

    // ── C) leave, and prove nothing was kept ──
    await authService.logout();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    expect(guestSession.isActive, isFalse);
    expect(guestWorldIsSeeded, isFalse);
    expect(authService.currentUser, isNull);
    expect(newsPosts, isEmpty);
    expect(clubs, isEmpty);
    expect(users, isEmpty);
    expect(userState.followedClubIds, isEmpty);
    await binding.takeScreenshot('guest-08-after-logout');
  });
}
