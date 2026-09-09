import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/widgets/clubup_design.dart';
import 'package:flutter_application_1/widgets/landing_design.dart';

/// `btn-guest` `631:17` on `Login Screen New ` (`630:116`) — the pill the new
/// FİRST LANDİNG PAGE frame adds to the top-left of the header band.
///
/// The pill is now wired: it opens the guest joyride through
/// `LoginScreen.onGuestLogin`. When that callback is not supplied the pill
/// stays inert exactly as the frame drew it — both halves are pinned below.
void main() {
  const pillKey = ValueKey<String>('landing-guest-login');
  const enToggleKey = ValueKey<String>('landing-language-en');

  // `flutter test` runs with `--use-test-fonts`, whose every glyph is a full em
  // wide — under it the Turkish label is ~70% wider than the real one and no
  // longer fits beside the switcher. Load the shipped Figtree so the width
  // assertions below measure what actually renders.
  setUpAll(() async {
    final loader = FontLoader(kClubUpFontFamily);
    for (final weight in const [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(
        File('assets/fonts/Figtree-$weight.ttf').readAsBytes().then(
          (bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
        ),
      );
    }
    await loader.load();
  });

  setUp(() async {
    await localeService.setLanguage('en');
    await themeService.setDark(true);
  });

  tearDown(() async {
    await localeService.setLanguage('en');
    await themeService.setDark(false);
  });

  Future<void> pumpLogin(
    WidgetTester tester, {
    String lang = 'en',
    VoidCallback? onGuestLogin,
  }) async {
    tester.view.physicalSize = const Size(402 * 3, 906 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 44 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(
          onLogin: () {},
          onSignUp: () {},
          onAdminLogin: () {},
          onGuestLogin: onGuestLogin,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sits 24 from the page edge, 28 tall, left of the switcher', (
    tester,
  ) async {
    await pumpLogin(tester);

    final pill = tester.getRect(find.byKey(pillKey));
    // `btn-guest` x=24, height=28 in the frame.
    expect(pill.left, closeTo(24, 0.01));
    expect(pill.height, closeTo(28, 0.01));

    // Below the status bar, and centred on the EN | TR switcher rather than
    // reproducing the frame's stray 6pt drop (the pill is a loose sibling of
    // `language-switcher` there, not a child of it).
    final toggle = tester.getRect(find.byKey(enToggleKey));
    expect(pill.top, greaterThanOrEqualTo(44));
    expect(pill.center.dy, closeTo(toggle.center.dy, 0.01));
    expect(pill.right, lessThan(toggle.left));
  });

  testWidgets('takes its natural width in English and in Turkish', (
    tester,
  ) async {
    // The trap this guards: a `Flexible` pill in a `Row` with a `Spacer`
    // becomes a flex child and shares the free space instead of hugging its
    // label, which trims the longer Turkish string to "Misafir Olarak D…".
    for (final lang in const ['en', 'tr']) {
      await localeService.setLanguage(lang);
      await pumpLogin(tester, lang: lang);

      final label = S.landingGuestLogin;
      expect(find.text(label), findsOneWidget);

      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: figtree(
            size: 13,
            weight: FontWeight.w600,
            height: 16 / 13,
            letterSpacing: 0,
            color: const Color(0xFFFAFAFA),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // `text` x=12 w=110 inside a 134-wide pill → label + 2×12.
      expect(
        tester.getSize(find.byKey(pillKey)).width,
        closeTo(painter.width + 24, 0.5),
        reason: 'pill was clipped or stretched in $lang',
      );
    }
  });

  testWidgets('is burgundy with a near-white SemiBold label', (tester) async {
    await pumpLogin(tester);

    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(pillKey),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    // `#800021` in the frame — one blue step off the area's `accent` token.
    expect(decoration.color, LandingColors.accent);
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(999)),
    );

    final style = tester
        .widget<Text>(find.text(S.landingGuestLogin))
        .style!;
    expect(style.color, const Color(0xFFFAFAFA));
    expect(style.fontSize, 13);
    expect(style.fontWeight, FontWeight.w600);
    // Not Material's inherited 0.25 on `bodyMedium`: the frame tracks at 0.
    expect(style.letterSpacing, 0);
  });

  testWidgets('pressing it opens the guest joyride', (tester) async {
    var opened = 0;
    await pumpLogin(tester, onGuestLogin: () => opened++);

    await tester.tap(find.byKey(pillKey));
    await tester.pumpAndSettle();

    // The host owns the session change, so all this screen must do is report
    // the tap once.
    expect(opened, 1);
  });

  testWidgets('stays inert when no guest session is offered', (tester) async {
    await pumpLogin(tester);

    final before = tester.widgetList(find.byType(Widget)).length;
    await tester.tap(find.byKey(pillKey));
    await tester.pumpAndSettle();

    // With a null `onGuestLogin` the GestureDetector registers no recognizer
    // at all: no navigation, no ink, no error. Hosts that reuse LoginScreen
    // without a session to give (the sign-up flow) rely on this.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(pillKey), findsOneWidget);
    expect(find.text(S.landingGuestLogin), findsOneWidget);
    expect(tester.widgetList(find.byType(Widget)).length, before);
  });
}
