import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/content_audience.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/widgets/content_audience_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The picker is the only place a club is told what the three tiers mean, so
/// the descriptions matter as much as the labels.
void main() {
  setUp(() async {
    await themeService.setDark(false);
    await localeService.setLanguage('en');
  });

  tearDown(() async {
    await localeService.setLanguage('en');
    await themeService.setDark(false);
  });

  Future<ContentAudience?> openSheet(
    WidgetTester tester, {
    ContentAudience current = ContentAudience.everyone,
  }) async {
    ContentAudience? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(localeService.languageCode),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened = true;
                  result = await showContentAudienceSheet(
                    context,
                    current: current,
                    surface: Colors.white,
                    border: const Color(0xFFE4E4E7),
                    text: const Color(0xFF18181B),
                    muted: const Color(0xFF71717A),
                    accent: const Color(0xFF800020),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(opened, isTrue);
    return result;
  }

  testWidgets('all three tiers render with their explanations', (tester) async {
    await openSheet(tester);

    expect(find.byKey(const ValueKey('content-audience-sheet')), findsOneWidget);
    expect(find.text(S.audienceSheetTitle), findsOneWidget);
    for (final audience in ContentAudience.values) {
      expect(
        find.byKey(ValueKey('content-audience-option-${audience.wireValue}')),
        findsOneWidget,
        reason: '${audience.name} row is missing',
      );
      expect(find.text(S.audienceTierLabel(audience)), findsOneWidget);
      expect(find.text(S.audienceTierHint(audience)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the current tier is the selected row', (tester) async {
    await openSheet(tester, current: ContentAudience.followers);

    // Exactly one row carries the filled ring, and it is the current tier.
    expect(
      find.byKey(const ValueKey('content-audience-selected-followers')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('content-audience-selected-everyone')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('content-audience-selected-board')),
      findsNothing,
    );
    // And every row is announced as a button to a screen reader.
    for (final audience in ContentAudience.values) {
      final node = tester.getSemantics(
        find.byKey(ValueKey('content-audience-option-${audience.wireValue}')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a row pops that tier', (tester) async {
    ContentAudience? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showContentAudienceSheet(
                    context,
                    current: ContentAudience.everyone,
                    surface: Colors.white,
                    border: const Color(0xFFE4E4E7),
                    text: const Color(0xFF18181B),
                    muted: const Color(0xFF71717A),
                    accent: const Color(0xFF800020),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await tester.tap(
      find.byKey(const ValueKey('content-audience-option-board')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(picked, ContentAudience.board);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the copy switches to Turkish with the app language', (
    tester,
  ) async {
    await localeService.setLanguage('tr');
    await openSheet(tester);

    expect(find.text('Herkes'), findsOneWidget);
    expect(find.text('Yönetim kurulu'), findsOneWidget);
    expect(find.text('Kulübünü takip edenler'), findsOneWidget);
    expect(find.text('Everyone'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill renders only for restricted tiers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Column(
            children: [
              ContentAudiencePill(
                audience: ContentAudience.everyone,
                accent: Color(0xFF800020),
              ),
              ContentAudiencePill(
                audience: ContentAudience.board,
                accent: Color(0xFF800020),
              ),
              ContentAudiencePill.onMedia(audience: ContentAudience.followers),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(S.audienceTierPill(ContentAudience.board)), findsOneWidget);
    expect(
      find.text(S.audienceTierPill(ContentAudience.followers)),
      findsOneWidget,
    );
    // Public content carries no badge at all: two restricted pills are on
    // screen and three were built.
    expect(find.byIcon(audienceTierIcon(ContentAudience.board)), findsOneWidget);
    expect(
      find.byIcon(audienceTierIcon(ContentAudience.followers)),
      findsOneWidget,
    );
    expect(
      find.byIcon(audienceTierIcon(ContentAudience.everyone)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('each restricted tier gets its own glyph', (tester) async {
    // The badge is read at 11-13px, often before its label. A padlock and a
    // pair of people are distinguishable at that size; two copies of the same
    // eye are not.
    expect(
      audienceTierIcon(ContentAudience.board),
      isNot(audienceTierIcon(ContentAudience.followers)),
    );
    expect(audienceTierIcon(ContentAudience.board), Icons.lock_outline);
    expect(audienceTierIcon(ContentAudience.followers), Icons.group_outlined);
  });

  testWidgets('the media variant brings its own contrast', (tester) async {
    // Over a cover photo the club accent is unusable — a 10% wash of anything
    // disappears, and the accent itself may match the photo. The variant that
    // sits on media therefore ignores the accent entirely.
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ContentAudiencePill.onMedia(audience: ContentAudience.board),
        ),
      ),
    );
    await tester.pump();

    final icon = tester.widget<Icon>(
      find.byIcon(audienceTierIcon(ContentAudience.board)),
    );
    expect(icon.color, Colors.white);

    final label = tester.widget<Text>(
      find.text(S.audienceTierPill(ContentAudience.board)),
    );
    expect(label.style?.color, Colors.white);

    final box = tester.widget<Container>(
      find.ancestor(
        of: find.byIcon(audienceTierIcon(ContentAudience.board)),
        matching: find.byType(Container),
      ),
    );
    final fill = (box.decoration as BoxDecoration).color!;
    // A real scrim, not a 10% tint, or white text on a photo is unreadable.
    expect(fill.a, greaterThan(0.4));
    expect(tester.takeException(), isNull);
  });
}
