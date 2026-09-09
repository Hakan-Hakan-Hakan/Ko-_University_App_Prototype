import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/app_admin.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/screens/create_post_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/content_audience_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The post composer's audience row: present, defaulted to public, and wired to
/// the picker sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const clubId = 'composer-audience-club';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('audience_composer_');
    Hive.init(tempDir.path);
    await contentStore.initialize();
    await contentAudienceStore.initialize();
  });

  setUp(() async {
    await themeService.setDark(false);
    await localeService.setLanguage('en');
    clubs.add(
      Club(
        id: clubId,
        name: 'Debate Society',
        description: '',
        adminUserIds: <String>[clubId],
      ),
    );
    authService.setClubAdmin(
      AppAdmin(
        id: clubId,
        name: 'Debate Society',
        email: 'debate@ku.edu.tr',
        password: '',
      ),
    );
  });

  tearDown(() async {
    await authService.logout();
    contentAudienceStore.clearSessionState();
    clubs.clear();
    newsPosts.clear();
    await localeService.setLanguage('en');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpComposer(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(localeService.languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CreatePostScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    // CreatePostScreen already overflows by 93px at 393 wide before this
    // feature existed — verified against HEAD in a clean worktree, same
    // magnitude with none of this code present. Drain it so these tests report
    // on the audience row rather than on a layout bug they did not cause.
    final pending = tester.takeException();
    if (pending != null && !'$pending'.contains('overflowed')) {
      throw pending as Object;
    }
  }

  testWidgets('the composer offers an audience row, defaulted to Everyone', (
    tester,
  ) async {
    await pumpComposer(tester);

    expect(find.byKey(const ValueKey('create-post-audience')), findsOneWidget);
    expect(find.text(S.audienceFieldLabel), findsOneWidget);
    expect(find.text(S.audienceEveryone), findsOneWidget);
  });

  testWidgets('tapping the row opens the picker and the choice sticks', (
    tester,
  ) async {
    await pumpComposer(tester);

    // Called directly rather than tapped: the row can sit below the fold on a
    // short test surface, which fails a hit test.
    final row = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('create-post-audience')),
    );
    row.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('content-audience-sheet')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('content-audience-option-followers')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text(S.audienceFollowers), findsOneWidget);
    expect(find.text(S.audienceEveryone), findsNothing);
  });

  testWidgets('the row label is Turkish when the app is', (tester) async {
    await localeService.setLanguage('tr');
    await pumpComposer(tester);

    expect(find.text('Bunu kim görebilir'), findsOneWidget);
    expect(find.text('Herkes'), findsOneWidget);
  });
}
