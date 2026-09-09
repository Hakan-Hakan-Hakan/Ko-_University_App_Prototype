import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/screens/explore_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/people_service.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_application_1/widgets/search_filter_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// These drive the redesigned search screen from the ClubUp-Desings
/// STUDENT SEARCH handoff: the Discover Clubs / Find People tabs are gone, and
/// the major filter now lives behind the search field's Filters sheet
/// (filter button → "Major" row → Select Major picker → Done → Apply).
AppLocalizations get l10n =>
    lookupAppLocalizations(Locale(localeService.languageCode));

void main() {
  const engineeringId = 'major-filter-engineering';
  const ampersandEngineeringId = 'major-filter-ampersand-engineering';
  const economicsId = 'major-filter-economics';
  const missingMajorId = 'major-filter-missing';

  setUpAll(() {
    for (final user in [
      User(
        id: engineeringId,
        name: 'Ada Engineering',
        email: 'ada.engineering@ku.edu.tr',
        password: '',
        role: 'student',
        subscribedClubIds: const [],
      ),
      User(
        id: ampersandEngineeringId,
        name: 'Derya Chemical',
        email: 'derya.chemical@ku.edu.tr',
        password: '',
        role: 'student',
        subscribedClubIds: const [],
      ),
      User(
        id: economicsId,
        name: 'Bora Economics',
        email: 'bora.economics@ku.edu.tr',
        password: '',
        role: 'student',
        subscribedClubIds: const [],
      ),
      User(
        id: missingMajorId,
        name: 'Cem Undeclared',
        email: 'cem.undeclared@ku.edu.tr',
        password: '',
        role: 'student',
        subscribedClubIds: const [],
      ),
    ]) {
      peopleService.cacheRegisteredUser(user);
    }
  });

  setUp(() async {
    authService.logout();
    await localeService.setLanguage('en');
    await themeService.setDark(true);
    userState.setMajor(engineeringId, 'Computer Engineering');
    userState.setMajor(
      ampersandEngineeringId,
      'Chemical & Biological Engineering',
    );
    userState.setMajor(economicsId, 'Economics');
    userState.setMajor(missingMajorId, '');
  });

  tearDown(() async {
    authService.logout();
    await localeService.setLanguage('en');
    await themeService.setDark(true);
  });

  Future<void> pumpFindPeople(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(localeService.languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ExploreScreen(initialTabIndex: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('search-filter-button')));
    await tester.pumpAndSettle();
  }

  Future<void> applyFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('search-filters-apply')));
    await tester.pumpAndSettle();
  }

  Future<void> selectMajor(WidgetTester tester, String major) async {
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('people-major-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('academic-program-picker-search')),
      major,
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('academic-program-$major')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('major-picker-done')));
    await tester.pumpAndSettle();
    await applyFilters(tester);
  }

  testWidgets('Filters sheet searches clubs and students, but not events', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(localeService.languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ExploreScreen(),
        ),
      ),
    );
    await tester.pump();
    await openFilters(tester);

    expect(find.text('Search In'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Events'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'major-only filtering includes only exact primary-major matches',
    (tester) async {
      await pumpFindPeople(tester);

      expect(find.text('Ada Engineering'), findsOneWidget);
      expect(find.text('Bora Economics'), findsOneWidget);
      expect(find.text('Cem Undeclared'), findsOneWidget);

      await selectMajor(tester, 'Computer Engineering');

      expect(find.text('Ada Engineering'), findsOneWidget);
      expect(find.text('Bora Economics'), findsNothing);
      expect(find.text('Cem Undeclared'), findsNothing);
      expect(find.textContaining('1 RESULT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('name search intersects with the selected major and can clear', (
    tester,
  ) async {
    await pumpFindPeople(tester);
    await selectMajor(tester, 'Computer Engineering');

    final search = find.widgetWithText(TextField, l10n.searchEverythingHint);
    await tester.enterText(search, 'Bora');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bora Economics'), findsNothing);
    expect(find.text(S.noPeopleInSelectedMajor), findsOneWidget);

    await tester.enterText(search, 'Ada');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ada Engineering'), findsOneWidget);

    // Reset Filters closes the sheet and restores the original discovery UI.
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('clear-people-major-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-filters-apply')), findsNothing);
    expect(find.byKey(const ValueKey('search-discovery-list')), findsOneWidget);
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);

    // Re-enter Students with no major selected; the prior major filter should
    // not survive the global reset.
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('search-scope-students')));
    await applyFilters(tester);

    await tester.enterText(search, 'Bora');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bora Economics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('major filter and empty state are localized in Turkish', (
    tester,
  ) async {
    await localeService.setLanguage('tr');
    await themeService.setDark(false);
    await pumpFindPeople(tester);

    await openFilters(tester);
    expect(find.text(l10n.majorLabel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-filters-apply')));
    await tester.pumpAndSettle();

    await selectMajor(tester, 'Medicine');

    expect(find.text(S.noPeopleInSelectedMajor), findsOneWidget);
    expect(find.text(S.tryAnotherMajorOrName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ampersand engineering majors stay in Engineering', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-major-picker'),
              onPressed: () => showSearchMajorPicker(
                context: context,
                selected: const {},
                programs: const [
                  'Chemical & Biological Engineering',
                  'Electrical & Electronics Engineering',
                ],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-major-picker')));
    await tester.pumpAndSettle();

    expect(find.text('ENGINEERING'), findsOneWidget);
    expect(find.text('Chemical & Biological Engineering'), findsOneWidget);
    expect(find.text('Electrical & Electronics Engineering'), findsOneWidget);
    expect(find.text('ACADEMIC'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equivalent major spellings produce one working filter', (
    tester,
  ) async {
    await pumpFindPeople(tester);
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('people-major-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('academic-program-picker-search')),
      'Chemical',
    );
    await tester.pump();

    expect(find.text('Chemical and Biological Engineering'), findsOneWidget);
    expect(find.text('Chemical & Biological Engineering'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('academic-program-Chemical and Biological Engineering'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('major-picker-done')));
    await tester.pumpAndSettle();
    await applyFilters(tester);

    expect(find.text('Derya Chemical'), findsOneWidget);
    expect(find.textContaining('1 RESULT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
